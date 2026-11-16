# Maps a product to a search term (productType, falling back to title) and then
# to a Wikipedia article via search.
class ProductMapper
  # TODO(mapping overrides): merchants need to correct bad mappings (e.g. a vague
  # productType like "Kitchen" or a search that lands on the wrong article).
  # Plan: a SQLite table term_overrides(product_id, wikipedia_article) checked
  # before searching, editable from the page. Until then, this hash is the
  # stand-in, keyed by lowercase search term => exact Wikipedia article title.
  OVERRIDES = {}.freeze

  Mapping = Struct.new(:term, :source, :article, keyword_init: true)

  def initialize(wikipedia: WikipediaClient.new)
    @wikipedia = wikipedia
  end

  # product: { title:, product_type:, tags: }
  def call(product)
    if product[:product_type].present?
      term, source = product[:product_type], "productType"
    else
      term, source = product[:title], "title"
    end
    article = OVERRIDES[term.downcase] || @wikipedia.search_title(term)
    Mapping.new(term: term, source: source, article: article)
  end
end
