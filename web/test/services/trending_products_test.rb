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

  test "finds products on the most-read list, ranks them by momentum and runs the usual checks" do
    result = discover
    assert_equal ["Fidget spinner", "M&M's"], result.top.map(&:article), "the surge outranks the flat line"
    assert_empty result.others
    assert_in_delta 1.0, result.top.last.momentum, 1e-9, "flat 3,000/week: no momentum"
    spinner = result.top.first
    assert_operator spinner.momentum, :>, 1
    assert_match(/Likely (sustained|spike)/, spinner.result.label)
    assert_equal ["toy"], spinner.kinds
    assert_equal 26, spinner.recent.size
    assert_equal 3, result.scanned, "Main Page and Special: pages aren't candidates"
  end

  test "people and other non-products are dropped" do
    refute_includes (discover.top + discover.others).map(&:article), "Taylor Swift"
  end

  test "no lookahead: a replay reads the four weeks up to its last complete week, nothing after" do
    wikipedia = wiki
    result = discover(wikipedia)
    assert_equal Date.new(2017, 5, 29), result.week_start
    assert_equal Date.new(2017, 6, 4), result.week_end
    assert_equal Date.new(2017, 5, 8), result.lookback_start
    assert_equal (Date.new(2017, 5, 8)..Date.new(2017, 6, 4)).to_a, wikipedia.top_requests.uniq.sort
  end

  test "only the top five are ranked first; the rest follow in the same order" do
    titles = (1..7).map { |i| "Toy #{i}" }
    wikipedia = FakeWikipedia.new(top: ->(_date) { titles.map { |t| [t, 100_000] } },
                                  series: titles.each_with_index.to_h { |t, i| [t, [1000] * 30 + [1000 * (i + 1)]] },
                                  items: titles.each_with_index.to_h { |t, i| [t, [t, "Q#{i}"]] })
    result = TrendingProducts.call(as_of: AS_OF, wikipedia: wikipedia,
                                   wikidata: FakeWikidata.new(titles.each_index.to_h { |i| ["Q#{i}", ["toy"]] }))
    assert_equal ["Toy 7", "Toy 6", "Toy 5", "Toy 4", "Toy 3"], result.top.map(&:article)
    assert_equal ["Toy 2", "Toy 1"], result.others.map(&:article)
  end

  test "momentum: last week over the median of the 8 before, safe for brand-new articles" do
    assert_in_delta 4001.0 / 1001, TrendingProducts.momentum([1000] * 8 + [4000]), 1e-9
    assert_in_delta 5001.0, TrendingProducts.momentum([0] * 8 + [5000]), 1e-9
    assert_nil TrendingProducts.momentum([100])
  end

  test "candidates are ranked by views summed over the week" do
    top = ->(date) { date.wday == 1 ? [["M&M's", 900_000]] : [["Fidget spinner", 200_000], ["M&M's", 10_000]] }
    stub_const(TrendingProducts, :CANDIDATES, 1) do
      assert_equal ["Fidget spinner"], (discover(wiki(top: top)).top + discover(wiki(top: top)).others).map(&:article)
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
