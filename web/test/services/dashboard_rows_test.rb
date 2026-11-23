require "test_helper"

class DashboardRowsTest < ActiveSupport::TestCase
  setup do
    @real_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @products = [{ id: "1", title: "Matcha", product_type: "", tags: [] }]
  end

  teardown { Rails.cache = @real_cache }

  def fetch(wiki, overrides: OverrideSet.shared, products: @products)
    DashboardRows.fetch(products, as_of: Date.new(2026, 11, 16), overrides: overrides, wikipedia: wiki)
  end

  test "a second view reuses the labelled rows" do
    wiki = FakeWikipedia.new
    2.times { fetch(wiki) }
    assert_equal 1, wiki.series_requests.size
  end

  test "new products or overrides mean fresh rows, never stale ones" do
    wiki = FakeWikipedia.new
    fetch(wiki)
    fetch(wiki, products: @products + [{ id: "2", title: "Scrunchie", product_type: "", tags: [] }])
    session = {}
    OverrideSet.new(session: session).save_for_visitor("matcha", article: "Green tea")
    rows = fetch(wiki, overrides: OverrideSet.new(session: session))
    assert_equal "Green tea", rows.first.article
  end
end
