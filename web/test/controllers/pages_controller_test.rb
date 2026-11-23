require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "landing page has the hero, real stats and routes into the app" do
    get root_path
    assert_response :success
    assert_select "h1 em", "stay"
    assert_select ".stat-strip strong", text: TrendModel.instance.trained_on["n"].to_s
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
end
