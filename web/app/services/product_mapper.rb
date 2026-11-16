# Maps a product to a search term (productType, falling back to title) and then
# to a Wikipedia article via search, refusing mappings that are likely wrong.
class ProductMapper
  # TODO(mapping overrides): merchants need to correct bad mappings (e.g. a search
  # that lands on the wrong article). Plan: a SQLite table
  # term_overrides(product_id, wikipedia_article) checked before searching,
  # editable from the page. Until then, this hash is the stand-in, keyed by
  # lowercase search term => exact Wikipedia article title (skips all checks).
  OVERRIDES = {}.freeze

  # Product types too broad to stand for a trend. Compared after lowercasing and
  # removing everything but letters, so "Gift Card" and "giftcard" both match.
  GENERIC_TYPES = %w[
    accessories accessory apparel clothing default general giftcard giftcards
    merchandise misc miscellaneous other product products sample service
  ].to_set.freeze

  STOPWORDS = %w[a an and the of for with in on by to].to_set.freeze

  # article is nil when unmapped; `problem` then explains why.
  Mapping = Struct.new(:term, :source, :article, :redirected_from, :problem, keyword_init: true)

  def initialize(wikipedia: WikipediaClient.new)
    @wikipedia = wikipedia
  end

  # product: { title:, product_type:, tags: }
  def call(product)
    type = product[:product_type].to_s.strip
    if type.present?
      term, source = type, "productType"
      return unmapped(term, source, "Product type \"#{type}\" is too generic to map to a trend.") if generic?(type)
    else
      term, source = search_friendly(product[:title]), "title"
    end

    if (article = OVERRIDES[term.downcase])
      return Mapping.new(term: term, source: source, article: article)
    end

    hit = @wikipedia.search(term)
    return unmapped(term, source, "Wikipedia search found no article for \"#{term}\".") if hit.nil?
    unless plausible?(term, hit)
      return unmapped(term, source, "Search returned \"#{hit[:title]}\", which doesn't look like this product.")
    end

    Mapping.new(term: term, source: source, article: hit[:title], redirected_from: hit[:redirect_from])
  end

  private

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
