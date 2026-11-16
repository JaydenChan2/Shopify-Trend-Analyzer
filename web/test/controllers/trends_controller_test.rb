require "test_helper"

# Renders the whole page in demo mode with a fake Wikipedia (tests never load .env).
class TrendsControllerTest < ActionDispatch::IntegrationTest
  setup { TrendsController.wikipedia_client = FakeWikipedia.new }
  teardown { TrendsController.wikipedia_client = nil }

  test "page renders demo products with labels and a fix-mapping form per row" do
    get dashboard_path
    assert_response :success
    assert_select ".banner.info", /Demo mode/
    assert_select ".product-card", minimum: 1
    assert_select ".stat", minimum: 4
    assert_select "details.fix form[action=?]", mapping_overrides_path
  end

  test "an override changes the row's article and offers removal" do
    MappingOverride.create!(term_key: "matcha", article: "Green tea")
    get dashboard_path
    assert_select ".product-card .article", text: "Green tea"
    assert_select ".product-card .terms", text: /override/
    assert_select "form.fix-remove"
  end

  # Regression: an overridden product grouped under another product's article
  # must keep its own term and Remove button (found on the live store with snowboards).
  test "a grouped row lists every term and keeps the override's remove button" do
    MappingOverride.create!(term_key: "matcha", article: "Pickleball") # demo has a "Pickleball" product type
    get dashboard_path
    row = css_select(".product-card").find { |tr| tr.text.include?("Pickleball") && tr.text.include?("Matcha") }
    assert row, "Matcha should be grouped into the Pickleball row"
    assert_match "+1 more", row.text
    assert_equal 2, row.css("details.fix").size, "one fix form per term"
    assert_equal 1, row.css("form.fix-remove").size
  end

  # "Don't track" is its own form carrying ignored=1, so Save can never send it by accident.
  test "don't track is a separate form with a hidden ignored field" do
    get dashboard_path
    assert_select "details.fix form.fix-ignore input[type=hidden][name=ignored][value='1']"
    assert_select "details.fix form.fix-form input[name=ignored]", count: 0
  end

  test "labels render as pills with tones" do
    get dashboard_path
    assert_select ".label.tone-neutral", minimum: 1
  end

  test "cards carry a filter group, a sparkline and a link to the trend panel" do
    get dashboard_path
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
    get dashboard_path
    assert_select ".label", text: "Not tracked"
  end

  test "replay keeps as_of in the fix-mapping form" do
    get dashboard_path(as_of: "2017-06-12")
    assert_select ".banner.info", /Replay as of June 12, 2017/
    assert_select "details.fix input[name=as_of][value=?]", "2017-06-12"
  end
end
