require "test_helper"

class SeoControllerTest < ActionDispatch::IntegrationTest
  setup do
    TrendsController.wikipedia_client = FakeWikipedia.new
    DiscoverController.wikipedia_client = FakeWikipedia.new
    DiscoverController.wikidata_client = FakeWikidata.new
  end

  teardown do
    TrendsController.wikipedia_client = nil
    DiscoverController.wikipedia_client = nil
    DiscoverController.wikidata_client = nil
  end

  test "every page has a description, canonical link, Open Graph and Twitter tags" do
    [root_path, methodology_path, dashboard_path, discover_path, trend_path(article: "Matcha")].each do |path|
      get path
      assert_select "meta[name=description][content]", 1, path
      assert_select "link[rel=canonical][href=?]", "http://www.example.com#{path}"
      %w[og:title og:description og:type og:url og:image].each do |prop|
        assert_select "meta[property='#{prop}'][content]", 1, "#{path} #{prop}"
      end
      assert_select "meta[property='og:image'][content=?]", "http://www.example.com/og-image.png"
      assert_select "meta[name='twitter:card'][content=summary_large_image]"
    end
  end

  test "descriptions differ per page" do
    descriptions = [root_path, methodology_path, discover_path].map do |path|
      get path
      css_select("meta[name=description]").first["content"]
    end
    assert_equal 3, descriptions.uniq.size
  end

  test "replays canonicalise to the page without ?as_of" do
    get dashboard_path(as_of: "2017-06-12")
    assert_select "link[rel=canonical][href=?]", "http://www.example.com/dashboard"
  end

  test "sitemap lists the public pages with absolute URLs" do
    get "/sitemap.xml"
    assert_response :success
    assert_equal "application/xml", response.media_type
    %w[/ /discover /how-it-works /dashboard].each do |path|
      assert_includes response.body, "<loc>http://www.example.com#{path}</loc>"
    end
  end

  test "robots.txt points at the sitemap" do
    get "/robots.txt"
    assert_response :success
    assert_includes response.body, "Sitemap: http://www.example.com/sitemap.xml"
  end

  test "favicon, icon and og:image files exist" do
    %w[favicon.ico icon.svg icon.png og-image.png].each do |file|
      assert Rails.root.join("public", file).exist?, file
    end
  end

  test "footer column titles aren't headings (no skipped heading levels)" do
    get root_path
    assert_select "footer h2, footer h3, footer h4", 0
    assert_select "footer .footer-heading", 3
  end
end
