require "test_helper"

# Renders the whole page in demo mode with a fake Wikipedia (tests never load .env).
class TrendsControllerTest < ActionDispatch::IntegrationTest
  setup { TrendsController.wikipedia_client = FakeWikipedia.new }
  teardown { TrendsController.wikipedia_client = nil }

  test "page renders demo products with labels and a fix-mapping form per row" do
    get dashboard_path(inline: 1)
    assert_response :success
    assert_select ".banner.info", /Demo mode/
    assert_select ".product-card", minimum: 1
    assert_select ".stat", minimum: 4
    assert_select "details.fix form[action=?]", mapping_overrides_path
  end

  test "an override changes the row's article and offers removal" do
    MappingOverride.create!(term_key: "matcha", article: "Green tea")
    get dashboard_path(inline: 1)
    assert_select ".product-card .article", text: "Green tea"
    assert_select ".product-card .terms", text: /override/
    assert_select "form.fix-remove"
  end

  # Regression: an overridden product grouped under another product's article
  # must keep its own term and Remove button (found on the live store with snowboards).
  test "a grouped row lists every term and keeps the override's remove button" do
    MappingOverride.create!(term_key: "matcha", article: "Pickleball") # demo has a "Pickleball" product type
    get dashboard_path(inline: 1)
    row = css_select(".product-card").find { |tr| tr.text.include?("Pickleball") && tr.text.include?("Matcha") }
    assert row, "Matcha should be grouped into the Pickleball row"
    assert_match "+1 more", row.text
    assert_equal 2, row.css("details.fix").size, "one fix form per term"
    assert_equal 1, row.css("form.fix-remove").size
  end

  # "Don't track" is its own form carrying ignored=1, so Save can never send it by accident.
  test "don't track is a separate form with a hidden ignored field" do
    get dashboard_path(inline: 1)
    assert_select "details.fix form.fix-ignore input[type=hidden][name=ignored][value='1']"
    assert_select "details.fix form.fix-form input[name=ignored]", count: 0
  end

  test "labels render as pills with tones" do
    get dashboard_path(inline: 1)
    assert_select ".label.tone-neutral", minimum: 1
  end

  test "cards carry a filter group, a sparkline and a link to the trend panel" do
    get dashboard_path(inline: 1)
    assert_select ".product-card[data-group]", minimum: 1
    assert_select ".product-card svg.sparkline", minimum: 1
    assert_select ".product-card a.card-open[href^=?]", "/trend?"
    assert_select ".stat[data-filter=surge]"
    assert_select "dialog.trend-dialog"
  end

  # The trend panel
  SURGE = [1000] * 40 + [5000, 6000, 7000, 7500, 7000, 6800, 6500]

  test "trend panel for the dialog is just the fragment, with chart and explanation" do
    TrendsController.wikipedia_client = FakeWikipedia.new(series: { "Air fryer" => SURGE })
    get trend_path(article: "Air fryer", product: "5.8qt Basket Air Fryer"), xhr: true
    assert_response :success
    assert_select "header.site-nav", count: 0
    assert_select "h2", "5.8qt Basket Air Fryer"
    assert_select "svg.chart-svg[data-points]"
    assert_select ".chart .onset"
    assert_select ".chart .feature-window"
    assert_select ".explain .contrib li", 4
  end

  test "trend panel opened directly is a full page" do
    get trend_path(article: "Matcha")
    assert_response :success
    assert_select "header.site-nav"
    assert_select "a.back-link"
    assert_select "svg.chart-svg"
    assert_select ".explain", count: 0 # flat series: nothing scored
  end

  test "trend panel replay keeps as_of and says so" do
    get trend_path(article: "Matcha", as_of: "2017-06-12"), xhr: true
    assert_select "p.hint", /Replay as of June 12, 2017/
  end

  test "an ignored term shows as Not tracked" do
    MappingOverride.create!(term_key: "t-shirt", ignored: true)
    get dashboard_path(inline: 1)
    assert_select ".label", text: "Not tracked"
  end

  test "replay keeps as_of in the fix-mapping form" do
    get dashboard_path(as_of: "2017-06-12", inline: 1)
    assert_select ".banner.info", /Replay as of June 12, 2017/
    assert_select "details.fix input[name=as_of][value=?]", "2017-06-12"
  end

  # ---------- Hindsight on replays ----------
  # Pop Mart: 1,000/week, then a jump on 2020-01-06 that settles at 6,000/week (lasted).
  POP_MART_ONSET = Date.new(2020, 1, 6)

  def with_pop_mart_surge
    TrendsController.wikipedia_client = DatedFakeWikipedia.new(dated: {
      "Pop Mart" => ->(monday) {
        weeks_in = ((monday - POP_MART_ONSET) / 7).to_i
        weeks_in.negative? ? 1000 : [20_000, 15_000, 12_000, 10_000, 9000, 8000].fetch(weeks_in, 6000)
      }
    })
    MappingOverride.create!(term_key: "matcha", article: "Pop Mart")
  end

  test "a replay shows whether each call came true, with a tally" do
    with_pop_mart_surge
    get dashboard_path(as_of: (POP_MART_ONSET + 8 * 7).iso8601, inline: 1)
    card = css_select(".product-card").find { |c| c.text.include?("Matcha") }
    assert_match(/Likely (sustained|spike)/, card.css(".label").text)
    assert_match(/Came true: it lasted|Missed: it lasted/, card.css(".hindsight-head").text)
    assert_match "averaged", card.css(".hindsight-detail").text
    assert_select ".banner.hindsight-banner", /of 1 call came true/
    assert_empty card.css(".hindsight-warn"), "Pop Mart wasn't in the training data"
  end

  test "today's view never shows hindsight" do
    with_pop_mart_surge
    get dashboard_path(inline: 1)
    assert_select ".hindsight", count: 0
    assert_select ".hindsight-banner", count: 0
  end

  # ---------- header store pill ----------

  test "sample products show 'Demo store' in the header" do
    get dashboard_path(inline: 1)
    assert_select ".nav-status", "Demo store"
  end

  test "a real store shows its domain, truncatable, with the full domain as a title" do
    store = ProductSource::Result.new(products: [], mode: :shopify, shop: "a-very-long-store-name.myshopify.com")
    TrendsController.product_source = Struct.new(:result) { def call = result }.new(store)
    begin
      get dashboard_path(inline: 1)
      assert_select ".nav-status[title=?] .nav-shop", "a-very-long-store-name.myshopify.com", text: "a-very-long-store-name.myshopify.com"

      ENV["DEMO_MODE"] = "true"
      get dashboard_path(inline: 1)
      assert_select ".nav-status", "Demo store"
      assert_select ".nav-shop", 0
    ensure
      TrendsController.product_source = ProductSource
    end
  ensure
    ENV.delete("DEMO_MODE")
  end

  # ---------- page shell + cards loaded after ----------

  test "the dashboard shell renders without touching Wikipedia, with a loading state" do
    wiki = FakeWikipedia.new
    TrendsController.wikipedia_client = wiki
    get dashboard_path(as_of: "2017-06-12")
    assert_response :success
    assert_empty wiki.series_requests, "no Wikipedia calls for the shell"
    assert_select ".lazy[data-lazy-src=?][aria-busy=true]", dashboard_cards_path(as_of: "2017-06-12")
    assert_select ".lazy noscript", /Show products/
    assert_select ".banner.info", /Replay as of June 12, 2017/
    assert_select ".product-card", 0
  end

  test "/dashboard/cards returns just the cards, keeping the replay date" do
    get dashboard_cards_path(as_of: "2017-06-12")
    assert_response :success
    assert_select ".product-card", minimum: 1
    assert_select ".site-nav", 0
    assert_select "details.fix input[name=as_of][value=?]", "2017-06-12"
  end
end
