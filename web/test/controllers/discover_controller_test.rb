require "test_helper"

class DiscoverControllerTest < ActionDispatch::IntegrationTest
  SURGE = [1000] * 40 + [5000, 6000, 7000, 7500, 7000, 6800, 6500] # onset 7 weeks before the end

  setup do
    DiscoverController.wikipedia_client = FakeWikipedia.new(
      top: ->(_date) { [["Fidget spinner", 300_000], ["M&M's", 50_000]] },
      series: { "Fidget spinner" => SURGE },
      items: { "Fidget spinner" => ["Fidget spinner", "Q1"], "M&M's" => ["M&M's", "Q3"] }
    )
    DiscoverController.wikidata_client = FakeWikidata.new("Q1" => ["toy"], "Q3" => ["food"])
  end

  teardown do
    DiscoverController.wikipedia_client = nil
    DiscoverController.wikidata_client = nil
  end

  test "shows surging products as cards and steady ones as a list" do
    get discover_path
    assert_response :success
    assert_select ".product-card", 1
    assert_select ".product-card .product-title", "Fidget spinner"
    assert_select ".product-card .pill", "toy"
    assert_select ".product-card a.card-open[href^=?]", "/trend?"
    assert_select ".steady-list li", 1
    assert_select ".steady-list a[data-trend]", "M&M's"
    assert_select ".banner.info", /most-read English Wikipedia articles/
  end

  test "no store mapping on Discover: no fix forms" do
    get discover_path
    assert_select "details.fix", 0
    assert_select ".product-card .article a[href^=?]", "https://en.wikipedia.org/wiki/"
  end

  test "replays carry the date and the hindsight tally" do
    get discover_path(as_of: "2017-06-12")
    assert_select ".banner.info", /Replay as of June 12, 2017/
    assert_select ".pill-accent", /Jun 12, 2017/
  end

  test "an empty week says so instead of showing nothing" do
    DiscoverController.wikipedia_client = FakeWikipedia.new
    get discover_path
    assert_select ".empty-state", /No product on the most-read list/
  end

  test "a Wikipedia outage shows a banner, not a crash" do
    broken = FakeWikipedia.new
    def broken.top_articles(_date) = raise(WikipediaClient::Error, "HTTP 503")
    DiscoverController.wikipedia_client = broken
    get discover_path
    assert_response :success
    assert_select ".banner.critical", /HTTP 503/
  end

  test "the nav links to Discover" do
    get root_path
    assert_select ".nav-links a[href=?]", discover_path
  end
end
