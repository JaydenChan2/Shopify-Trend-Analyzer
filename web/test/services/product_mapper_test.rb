require "test_helper"

class ProductMapperTest < ActiveSupport::TestCase
  # Stands in for WikipediaClient: records the term and returns a canned title.
  class FakeWikipedia
    attr_reader :searched
    def search_title(term)
      @searched = term
      "Article for #{term}"
    end
  end

  setup { @wiki = FakeWikipedia.new }

  test "uses productType when present" do
    m = ProductMapper.new(wikipedia: @wiki).call({ title: "5.8qt Basket Air Fryer", product_type: "Air fryer" })
    assert_equal ["Air fryer", "productType", "Article for Air fryer"], [m.term, m.source, m.article]
  end

  test "falls back to title when productType is blank" do
    m = ProductMapper.new(wikipedia: @wiki).call({ title: "Weighted Blanket", product_type: "" })
    assert_equal ["Weighted Blanket", "title"], [m.term, m.source]
    assert_equal "Weighted Blanket", @wiki.searched
  end
end
