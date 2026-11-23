# Maps a product to a search term (productType, falling back to title) and then
# to a Wikipedia article: an override if there is one (see OverrideSet), otherwise
# Wikipedia search, refusing search results that are likely wrong.
class ProductMapper
  # Product types too broad to stand for a trend. Compared after lowercasing and
  # removing everything but letters, so "Gift Card" and "giftcard" both match.
  GENERIC_TYPES = %w[
    accessories accessory apparel clothing default general giftcard giftcards
    merchandise misc miscellaneous other product products sample service
  ].to_set.freeze

  STOPWORDS = %w[a an and the of for with in on by to].to_set.freeze

  # article is nil when unmapped; `problem` then explains why.
  # override_scope is :shared or :session when an override decided the mapping
  # (override_id is the MappingOverride id for shared ones); ignored when it says "don't track".
  Mapping = Struct.new(:term, :source, :article, :redirected_from, :problem, :override_scope, :override_id, :ignored,
                       keyword_init: true)

  def initialize(wikipedia: WikipediaClient.new, overrides: OverrideSet.shared)
    @wikipedia = wikipedia
    @overrides = overrides
  end

  # product: { title:, product_type:, tags: }
  def call(product)
    type = product[:product_type].to_s.strip
    term, source = type.present? ? [type, "productType"] : [search_friendly(product[:title]), "title"]

    # The merchant's correction wins over everything else (search, sanity check, generic list).
    if (override = @overrides.lookup(term))
      return from_override(term, source, override)
    end
    if source == "productType" && generic?(type)
      return unmapped(term, source, "Product type \"#{type}\" is too generic to map to a trend.")
    end

    hit = @wikipedia.search(term)
    return unmapped(term, source, "Wikipedia search found no article for \"#{term}\".") if hit.nil?
    unless plausible?(term, hit)
      return unmapped(term, source, "Search returned \"#{hit[:title]}\", which doesn't look like this product.")
    end

    Mapping.new(term: term, source: source, article: hit[:title], redirected_from: hit[:redirect_from])
  end

  private

  def from_override(term, source, override)
    marks = { override_scope: override.scope, override_id: override.id }
    if override.ignored
      Mapping.new(term: term, source: source, ignored: true, problem: "Marked \"don't track\".", **marks)
    else
      Mapping.new(term: term, source: source, article: override.article, **marks)
    end
  end

  def unmapped(term, source, problem)
    Mapping.new(term: term, source: source, problem: problem)
  end

  def generic?(type)
    GENERIC_TYPES.include?(type.downcase.gsub(/[^a-z]/, ""))
  end

  # Drop sizes/quantities like "15lb" or "30g": they break Wikipedia search.
  def search_friendly(title)
    cleaned = title.to_s.split.reject { |word| word.match?(/\d/) }.join(" ")
    cleaned.presence || title.to_s
  end

  # Sanity check: every meaningful word of the article title (or of the redirect
  # it matched through) must appear in the search term. Catches "The Minimal
  # Snowboard" -> "1080° Snowboarding" (a video game): "1080" isn't in the term.
  def plausible?(term, hit)
    term_words = words(term)
    [hit[:title], hit[:redirect_from]].compact.any? do |candidate|
      candidate_words = words(candidate)
      candidate_words.any? && candidate_words.all? { |w| term_words.include?(w) }
    end
  end

  # Lowercase, drop "(disambiguation)" parts and stopwords, strip a plural "s".
  def words(text)
    text.downcase.gsub(/\(.*?\)/, " ").scan(/[[:alnum:]]+/)
        .reject { |w| STOPWORDS.include?(w) }
        .map { |w| w.length > 3 ? w.delete_suffix("s") : w }
        .to_set
  end
end
