require "test_helper"

class ProductTrendTest < ActiveSupport::TestCase
  # Fake Wikipedia: canned search results; weekly_views returns a flat series
  # (3,000/week, so "No surge detected") and records which article was asked for.
  class FakeWikipedia
    attr_reader :series_requests

    def initialize(results)
      @results = results
      @series_requests = []
    end

    def search(term)
      @results.fetch(term)
    end

    def weekly_views(article, through:)
      @series_requests << article
      mondays = (WikipediaClient::FIRST_MONDAY..through).step(7).select { |m| m + 6 <= through }
      mondays.map { |m| [m, 3000] }
    end
  end

  RESULTS = {
    "Snowboard" => { title: "Snowboard", redirect_from: nil },
    "Air fryer" => { title: "Convection oven", redirect_from: "Air fryer" }
  }.freeze

  def product(title, type)
    { title: title, product_type: type, tags: [] }
  end

  # Fix 5: grouping
  test "products mapping to the same article become one row with every product" do
    products = (1..15).map { |i| product("Snowboard #{i}", "Snowboard") } + [product("Gift Card", "giftcard")]
    wiki = FakeWikipedia.new(RESULTS)
    rows = ProductTrend.rows(products, as_of: Date.new(2026, 11, 15), wikipedia: wiki)

    assert_equal 2, rows.size
    snowboards = rows.find { |r| r.mapping.article == "Snowboard" }
    assert_equal 15, snowboards.products.size
    assert_equal ["Snowboard"], wiki.series_requests, "the article's views should be fetched once"
  end

  test "unmapped rows sort last" do
    rows = ProductTrend.rows([product("Gift Card", "giftcard"), product("Board", "Snowboard")],
                             as_of: Date.new(2026, 11, 15), wikipedia: FakeWikipedia.new(RESULTS))
    assert_equal ["No surge detected", "Not mapped"], rows.map { |r| r.result.label }
  end

  # Fix 1: the warning shows on the row today.
  test "redirected mapping carries a warning" do
    wiki = FakeWikipedia.new(RESULTS)
    row = ProductTrend.rows([product("Fryer", "Air fryer")], as_of: Date.new(2026, 11, 15), wikipedia: wiki).first
    assert_equal ["Convection oven"], wiki.series_requests
    assert_match "redirects to \"Convection oven\"", row.notes.first
  end

  # Fix 7: before the merge (2023-05-04 in backtest/trends.csv) replays use the old article's own views.
  test "replay before the merge uses the standalone article's views" do
    wiki = FakeWikipedia.new(RESULTS)
    row = ProductTrend.rows([product("Fryer", "Air fryer")], as_of: Date.new(2017, 12, 31), wikipedia: wiki).first
    assert_equal ["Air fryer"], wiki.series_requests
    assert_equal "Air fryer", row.article, "the table should name the article whose views were used"
    assert_match "was its own article until 2023-05-04", row.notes.first
  end

  test "replay after the merge uses the redirect target" do
    wiki = FakeWikipedia.new(RESULTS)
    ProductTrend.rows([product("Fryer", "Air fryer")], as_of: Date.new(2023, 6, 1), wikipedia: wiki)
    assert_equal ["Convection oven"], wiki.series_requests
  end
end
