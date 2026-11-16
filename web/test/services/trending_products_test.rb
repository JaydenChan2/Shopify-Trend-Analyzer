require "test_helper"

class TrendingProductsTest < ActiveSupport::TestCase
  AS_OF = Date.new(2017, 6, 12) # last complete week: May 29 - Jun 4
  SURGE = [1000] * 40 + [5000, 6000, 7000, 7500, 7000, 6800, 6500] # onset 7 weeks before the end

  def wiki(top: nil)
    top ||= ->(_date) { [["Main Page", 9_000_000], ["Special:Search", 500_000], ["Fidget spinner", 300_000],
                         ["Taylor Swift", 200_000], ["M&M's", 50_000]] }
    FakeWikipedia.new(top: top, series: { "Fidget spinner" => SURGE },
                      items: { "Fidget spinner" => ["Fidget spinner", "Q1"], "Taylor Swift" => ["Taylor Swift", "Q2"],
                               "M&M's" => ["M&M's", "Q3"] })
  end

  def discover(wikipedia = wiki)
    TrendingProducts.call(as_of: AS_OF, wikipedia: wikipedia,
                          wikidata: FakeWikidata.new("Q1" => ["toy"], "Q3" => ["food", "brand"]))
  end

  test "finds products on the most-read list and runs the usual checks" do
    result = discover
    assert_equal ["Fidget spinner"], result.surging.map(&:article)
    assert_equal ["M&M's"], result.steady.map(&:article), "flat 3,000/week: no jump"
    spinner = result.surging.first
    assert_match(/Likely (sustained|spike)/, spinner.result.label)
    assert_equal ["toy"], spinner.kinds
    assert_equal 26, spinner.recent.size
    assert_equal 3, result.scanned, "Main Page and Special: pages aren't candidates"
  end

  test "people and other non-products are dropped" do
    refute_includes (discover.surging + discover.steady).map(&:article), "Taylor Swift"
  end

  test "no lookahead: a replay only reads top lists up to its last complete week" do
    wikipedia = wiki
    result = discover(wikipedia)
    assert_equal Date.new(2017, 5, 29), result.week_start
    assert_equal Date.new(2017, 6, 4), result.week_end
    assert_equal (Date.new(2017, 5, 29)..Date.new(2017, 6, 4)).to_a, wikipedia.top_requests.sort
  end

  test "candidates are ranked by views summed over the week" do
    top = ->(date) { date.wday == 1 ? [["M&M's", 900_000]] : [["Fidget spinner", 200_000], ["M&M's", 10_000]] }
    stub_const(TrendingProducts, :CANDIDATES, 1) do
      assert_equal ["Fidget spinner"], (discover(wiki(top: top)).surging + discover(wiki(top: top)).steady).map(&:article)
    end
  end

  private

  def stub_const(klass, name, value)
    old = klass.const_get(name)
    klass.send(:remove_const, name)
    klass.const_set(name, value)
    yield
  ensure
    klass.send(:remove_const, name)
    klass.const_set(name, old)
  end
end
