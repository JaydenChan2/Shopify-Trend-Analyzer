require "test_helper"

class ProductMapperTest < ActiveSupport::TestCase
  # Stands in for WikipediaClient: canned search results keyed by term.
  class FakeWikipedia
    attr_reader :searched

    def initialize(results = {})
      @results = results
      @searched = []
    end

    def search(term)
      @searched << term
      @results.fetch(term) { { title: term.capitalize, redirect_from: nil } }
    end
  end

  def map(product, results = {})
    @wiki = FakeWikipedia.new(results)
    ProductMapper.new(wikipedia: @wiki).call(product)
  end

  test "uses productType when present" do
    m = map({ title: "5.8qt Basket Fryer", product_type: "Pickleball" })
    assert_equal ["Pickleball", "productType", "Pickleball"], [m.term, m.source, m.article]
  end

  test "falls back to title, dropping sizes like 15lb that break search" do
    m = map({ title: "Weighted Blanket 15lb", product_type: "" })
    assert_equal ["Weighted Blanket", "title"], [m.term, m.source]
    assert_equal ["Weighted Blanket"], @wiki.searched
  end

  # Fix 1: the redirect is recorded so the row can warn about it.
  test "records when the match came through a redirect" do
    m = map({ title: "Fryer", product_type: "Air fryer" },
            "Air fryer" => { title: "Convection oven", redirect_from: "Air fryer" })
    assert_equal "Convection oven", m.article
    assert_equal "Air fryer", m.redirected_from
  end

  # Fix 2: the real case from the dev store.
  test "rejects a search result that doesn't look like the product" do
    m = map({ title: "The Minimal Snowboard", product_type: "" },
            "The Minimal Snowboard" => { title: "1080° Snowboarding", redirect_from: nil })
    assert_nil m.article
    assert_match "1080° Snowboarding", m.problem
  end

  test "accepts plurals and ignores disambiguation in parentheses" do
    m = map({ title: "Squishy Toys", product_type: "" }, "Squishy Toys" => { title: "Squishy (toy)", redirect_from: nil })
    assert_equal "Squishy (toy)", m.article
  end

  # Fix 3
  test "generic product types are not mapped or searched" do
    ["accessories", "Gift Card", "giftcard", "Other"].each do |type|
      m = map({ title: "Something", product_type: type })
      assert_nil m.article, type
      assert_match "too generic", m.problem
      assert_empty @wiki.searched
    end
  end

  # Option 2: merchant overrides beat search, the sanity check and the generic list.
  test "an override decides the article without searching" do
    override = MappingOverride.create!(term_key: "the minimal snowboard", article: "Snowboard")
    m = map({ title: "The Minimal Snowboard", product_type: "" })
    assert_equal ["Snowboard", override.id, :shared], [m.article, m.override_id, m.override_scope]
    assert_empty @wiki.searched
  end

  test "an ignored override marks the term as not tracked, even for generic types" do
    MappingOverride.create!(term_key: "giftcard", ignored: true)
    m = map({ title: "Gift Card", product_type: "giftcard" })
    assert m.ignored
    assert_nil m.article
  end

  test "generic check applies to product types, not titles" do
    m = map({ title: "Other", product_type: "" }, "Other" => { title: "Other", redirect_from: nil })
    assert_equal "Other", m.article
  end

  test "no search result means not mapped" do
    m = map({ title: "Zzz", product_type: "Zzzqx" }, "Zzzqx" => nil)
    assert_nil m.article
    assert_match "found no article", m.problem
  end
end
