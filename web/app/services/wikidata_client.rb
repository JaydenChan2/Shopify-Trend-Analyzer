# Asks Wikidata what kind of thing each item is, so Discover can keep products
# (toys, food, gadgets...) and drop people, films, events and so on.
#
# Two steps, because hundreds of items share a few hundred types (most are "human"):
#   1. each item's direct types: "instance of" (P31) and "subclass of" (P279)
#   2. each distinct type: which KINDS/EXCLUDED classes it falls under, following
#      "subclass of" chains upward. Parents rarely change: they're cached for 30
#      days and a snapshot ships in db/wikidata_parents.json, so a cold start is fast.
# e.g. Fidget spinner -> toy; Labubu -> toy, brand; ChatGPT -> software (excluded).
class WikidataClient
  include WikimediaHttp

  SPARQL_API = "https://query.wikidata.org/sparql".freeze

  # Product kinds, in the order they're shown (first match is the card's tag).
  # Deliberately narrow. Tried and dropped: "game" (pulled in the Premier League,
  # Formula One, chess) and "product model" (bombers, missiles, car models).
  KINDS = {
    "Q11422" => "toy", "Q2095" => "food", "Q40050" => "drink", "Q11460" => "clothing",
    "Q131746" => "cosmetics", "Q212920" => "home appliance", "Q5193377" => "electronics",
    "Q131436" => "tabletop game", "Q431289" => "brand"
  }.freeze

  # Things that match a kind but aren't something a store stocks off the shelf.
  # (Medication is only excluded when the item isn't also food or drink: matcha is both.)
  EXCLUDED = {
    "Q7397" => "software", "Q7889" => "video game", "Q11424" => "film", "Q12140" => "medication",
    "Q196600" => "media franchise", "Q728" => "weapon"
  }.freeze
  HARD_EXCLUDED = (EXCLUDED.values - ["medication"]).freeze
  ROOTS = KINDS.merge(EXCLUDED).freeze

  # { "Q123" => ["toy", "brand"], ... } with only items that count as products.
  def product_kinds(qids)
    types = direct_types(qids.uniq)                      # item => [type, ...]
    roots = roots_of(types.values.flatten.uniq)          # type => ["toy", "software", ...]
    types.each_with_object({}) do |(qid, item_types), out|
      kinds = self.class.kinds_from(item_types.flat_map { |t| roots.fetch(t, []) }.uniq)
      out[qid] = kinds if kinds.any?
    end
  end

  # Class labels (KINDS and EXCLUDED values) -> product kinds, or [] if it isn't a product.
  def self.kinds_from(labels)
    return [] if labels.intersect?(HARD_EXCLUDED)
    return [] if labels.include?("medication") && !labels.intersect?(%w[food drink])

    KINDS.values & labels
  end

  # Every type -> parents link loaded or looked up so far (the rake task saves it).
  def known_parents = parents

  private

  # Step 1: { item => [direct type, ...] }. Cheap: no chains followed.
  def direct_types(qids)
    rows = in_parallel(qids.each_slice(100).to_a) do |batch|
      Rails.cache.fetch(["wikidata-types-v1", batch.sort], expires_in: 7.days) do
        sparql(<<~SPARQL).map { |row| [qid(row, "item"), qid(row, "type")] }.select { |_, type| item_id?(type) }
          SELECT ?item ?type WHERE {
            VALUES ?item { #{batch.map { |q| "wd:#{q}" }.join(' ')} }
            { ?item wdt:P31 ?type } UNION { ?item wdt:P279 ?type }
          }
        SPARQL
      end
    end.flatten(1)
    rows.each_with_object(Hash.new { |h, k| h[k] = [] }) { |(item, type), out| out[item] << type }
  end

  # Step 2: { type => [root label, ...] }, by walking "subclass of" (P279) upward one
  # level at a time from every type at once, up to MAX_DEPTH levels. Walking it here
  # instead of with a SPARQL property path (?type wdt:P279* ?root) because those
  # queries took 2-100s and sometimes failed with HTTP 502; one-hop lookups are fast.
  MAX_DEPTH = 12

  def roots_of(types)
    visited = Set.new
    frontier = types
    MAX_DEPTH.times do
      frontier = frontier.reject { |t| ROOTS.key?(t) || !visited.add?(t) } # roots: no need to climb higher
      break if frontier.empty?

      fetch_parents(frontier.reject { |t| parents.key?(t) }) # only the unknown ones hit the network
      frontier = frontier.flat_map { |t| parents[t] }.uniq
    end
    types.to_h { |t| [t, roots_above(t)] }
  end

  # Root labels reachable from `type` through known parents (no network).
  def roots_above(type)
    seen = Set.new
    queue = [type]
    found = []
    while (t = queue.shift)
      next unless seen.add?(t)
      next found << ROOTS[t] if ROOTS.key?(t) # don't climb past a root

      queue.concat(parents.fetch(t, []))
    end
    found.uniq
  end

  # type => [parent types]: the shipped catalog (db/wikidata_parents.json), plus
  # anything looked up since. See lib/tasks/discover.rake to refresh the catalog.
  def parents
    @parents ||= self.class.catalog.dup
  end

  def self.catalog
    @catalog ||= CATALOG_PATH.exist? ? JSON.parse(CATALOG_PATH.read) : {}
  end
  CATALOG_PATH = Rails.root.join("db", "wikidata_parents.json")

  def fetch_parents(types)
    cached = Rails.cache.read_multi(*types.map { |t| parents_key(t) })
    types.each { |t| parents[t] = cached[parents_key(t)] if cached.key?(parents_key(t)) }
    types.reject { |t| parents.key?(t) }.each_slice(150) do |batch|
      found = batch.to_h { |t| [t, []] }
      sparql(<<~SPARQL).each { |row| found[qid(row, "type")] << qid(row, "parent") if item_id?(qid(row, "parent")) }
        SELECT ?type ?parent WHERE {
          VALUES ?type { #{batch.map { |q| "wd:#{q}" }.join(' ')} }
          ?type wdt:P279 ?parent
        }
      SPARQL
      found.each do |t, ps|
        parents[t] = ps.uniq
        Rails.cache.write(parents_key(t), parents[t], expires_in: 30.days)
      end
    end
  end

  def parents_key(type) = ["wikidata-parents-v1", type]

  def sparql(query)
    uri = URI(SPARQL_API)
    uri.query = URI.encode_www_form(query: query, format: "json")
    JSON.parse(get(uri, accept: "application/sparql-results+json", read_timeout: 60).body).dig("results", "bindings")
  end

  def qid(row, var) = row.dig(var, "value").split("/").last

  # "Unknown value" statements come back as blank nodes (.well-known/genid/<hash>), not items.
  def item_id?(id) = id.match?(/\AQ\d+\z/)
end
