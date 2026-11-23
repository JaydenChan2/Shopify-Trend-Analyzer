# The mapping overrides that apply to one request.
#
#   shared:  MappingOverride rows (the seeded defaults, plus a real store's own fixes)
#   session: in demo mode only, this visitor's changes, layered on top. Stored in
#            the (encrypted, signed) session cookie, so they never reach other visitors.
#
# A session entry can point a term at an article, mark it "don't track", or hide a
# shared override for this visitor ("removed": back to automatic search).
class OverrideSet
  SESSION_KEY = "demo_overrides"
  MAX_SESSION_ENTRIES = 30 # the session cookie holds ~4 KB

  # scope: :shared or :session. id: the MappingOverride id (shared only).
  Entry = Struct.new(:term_key, :article, :ignored, :scope, :id, keyword_init: true)

  # Overrides for this request: shared, plus the visitor's own in demo mode.
  def self.for(session)
    new(session: DemoMode.on? ? session : nil)
  end

  # Shared overrides only (what every visitor sees).
  def self.shared
    new(session: nil)
  end

  def self.normalize(term)
    term.to_s.strip.downcase
  end

  def initialize(session:)
    @session = session
  end

  def session_scoped?
    !@session.nil?
  end

  # Changes whenever the overrides that apply to this request change (for cache keys).
  def fingerprint
    shared = MappingOverride.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(updated_at)"))
    own = session_scoped? ? session_entries.sort.to_h : {}
    Digest::SHA256.hexdigest([shared, own].to_json)[0, 16]
  end

  # The override deciding `term`, or nil (automatic search).
  def lookup(term)
    key = self.class.normalize(term)
    if session_scoped? && (own = session_entries[key])
      return nil if own["removed"]

      return Entry.new(term_key: key, article: own["article"], ignored: own["ignored"].present?, scope: :session)
    end

    shared = MappingOverride.for_term(key)
    shared && Entry.new(term_key: key, article: shared.article, ignored: shared.ignored?, scope: :shared, id: shared.id)
  end

  # ---------- writes (demo mode: this visitor's session only) ----------

  def save_for_visitor(term, article: nil, ignored: false)
    write(term, ignored ? { "ignored" => true } : { "article" => article })
  end

  # Back to the shared default if there is one; with no default, automatic search.
  # Removing a shared default hides it for this visitor only.
  def remove_for_visitor(term)
    key = self.class.normalize(term)
    entries = session_entries.except(key)
    entries[key] = { "removed" => true } if MappingOverride.for_term(key) && !session_entries.key?(key)
    @session[SESSION_KEY] = entries
  end

  private

  def session_entries
    @session[SESSION_KEY] || {}
  end

  def write(term, value)
    key = self.class.normalize(term)
    entries = session_entries.except(key)
    entries.shift while entries.size >= MAX_SESSION_ENTRIES # drop the oldest
    @session[SESSION_KEY] = entries.merge(key => value)
  end
end
