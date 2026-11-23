require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "landing page has the hero, real stats and routes into the app" do
    get root_path
    assert_response :success
    assert_select "h1", /whether a trend will stay/
    assert_select ".facts .stat-strip-n", TrendModel.instance.trained_on["n"].to_s
    assert_select ".fig-panel svg.fig-svg", 2 # Fig. 1: real series for both trends
    assert_select ".fig-panel", text: /Fidget spinner.*Likely spike · 73%/m
    assert_select ".fig-panel", text: /Air fryer.*Likely sustained · 67%/m
    assert_select "a[href=?]", dashboard_path, minimum: 1
    assert_select "a[href=?]", methodology_path, minimum: 1
    assert_select "a[href=?]", dashboard_path(as_of: "2017-12-31"), minimum: 1
    assert_select "#faq details", minimum: 3
  end

  test "landing page makes no Wikipedia or Shopify calls" do
    TrendsController.wikipedia_client = Object.new # would raise if anything tried to use it
    get root_path
    assert_response :success
  ensure
    TrendsController.wikipedia_client = nil
  end

  test "methodology page shows the rules, the results table with n, and limitations" do
    get methodology_path
    assert_response :success
    assert_select ".rule-card", minimum: 2
    assert_select "#results h2", /n = #{TrendModel.instance.trained_on["n"]}/
    assert_select "#results table.results tbody tr", 4
    assert_select "#limitations li", minimum: 4
  end

  test "nav links every page together" do
    get methodology_path
    assert_select ".site-nav a[href=?]", root_path
    assert_select ".site-nav a[href=?]", dashboard_path
  end

  test "every page has the theme toggle and applies a saved theme before paint" do
    [root_path, methodology_path, dashboard_path].each do |path|
      TrendsController.wikipedia_client = FakeWikipedia.new
      get path
      assert_select ".site-nav button.theme-toggle[data-theme-toggle][aria-pressed]", 1, path
      assert_select "head script", /localStorage\.getItem\("theme"\)/
    end
  ensure
    TrendsController.wikipedia_client = nil
  end

  test "mobile menu: a toggle that controls a panel with every nav link" do
    get root_path
    assert_select "button.menu-toggle[aria-controls=site-menu][aria-expanded=false][hidden]" # JS reveals it
    assert_select "nav#site-menu[hidden]" do
      assert_select "a[href=?]", discover_path
      assert_select "a[href=?]", methodology_path
      assert_select "a.btn", "Open dashboard"
    end
  end

  test "the header's Open dashboard button is hidden on the dashboard itself" do
    get dashboard_path
    assert_select ".nav-cta", 0
    assert_select "#site-menu a.btn", 0
    get discover_path
    assert_select ".nav-cta", "Open dashboard"
  end

  test "accuracy figures come from one source and agree on every page" do
    [root_path, methodology_path].each do |path|
      get path
      assert_includes response.body, "62.5%", path
      assert_includes response.body, "51–90%", path
      refute_match(/\b62%/, response.body, "#{path} still shows the rounded 62%")
    end
    get methodology_path
    assert_select "table.results tr.is-primary", /75%.*\[51–90\]/m
    assert_select ".callout", /12 vs 10/
  end

  test "dates for people use one format; the technical as_of stays ISO" do
    get root_path
    assert_includes response.body, "as_of = 2017-12-31"
    assert_includes response.body, "Dec 24, 2017"
  end

  test "Content-Security-Policy is on, and the one inline script carries its nonce" do
    get root_path
    policy = response.headers["Content-Security-Policy"]
    assert_match "default-src 'self'", policy
    assert_match "object-src 'none'", policy
    assert_match "frame-ancestors 'none'", policy
    nonce = policy[/script-src 'self' 'nonce-([^']+)'/, 1]
    assert nonce, "script-src has a nonce"
    assert_select "script:not([src])" do |scripts|
      scripts.each { |script| assert_equal nonce, script["nonce"] }
    end
  end
end
