require "test_helper"

# Renders the whole page in demo mode with a fake Wikipedia (tests never load .env).
class TrendsControllerTest < ActionDispatch::IntegrationTest
  setup { TrendsController.wikipedia_client = FakeWikipedia.new }
  teardown { TrendsController.wikipedia_client = nil }

  test "page renders demo products with labels and a fix-mapping form per row" do
    get root_path
    assert_response :success
    assert_select ".banner.info", /Demo mode/
    assert_select ".product-card", minimum: 1
    assert_select ".stat", minimum: 4
    assert_select "details.fix form[action=?]", mapping_overrides_path
  end

  test "an override changes the row's article and offers removal" do
    MappingOverride.create!(term_key: "matcha", article: "Green tea")
    get root_path
    assert_select ".product-card .article", text: "Green tea"
    assert_select ".product-card .terms", text: /override/
    assert_select "form.fix-remove"
  end

  # Regression: an overridden product grouped under another product's article
  # must keep its own term and Remove button (found on the live store with snowboards).
  test "a grouped row lists every term and keeps the override's remove button" do
    MappingOverride.create!(term_key: "matcha", article: "Pickleball") # demo has a "Pickleball" product type
    get root_path
    row = css_select(".product-card").find { |tr| tr.text.include?("Pickleball") && tr.text.include?("Matcha") }
    assert row, "Matcha should be grouped into the Pickleball row"
    assert_match "+1 more", row.text
    assert_equal 2, row.css("details.fix").size, "one fix form per term"
    assert_equal 1, row.css("form.fix-remove").size
  end

  # "Don't track" is its own form carrying ignored=1, so Save can never send it by accident.
  test "don't track is a separate form with a hidden ignored field" do
    get root_path
    assert_select "details.fix form.fix-ignore input[type=hidden][name=ignored][value='1']"
    assert_select "details.fix form.fix-form input[name=ignored]", count: 0
  end

  test "labels render as pills with tones" do
    get root_path
    assert_select ".label.tone-neutral", minimum: 1
  end

  test "an ignored term shows as Not tracked" do
    MappingOverride.create!(term_key: "t-shirt", ignored: true)
    get root_path
    assert_select ".label", text: "Not tracked"
  end

  test "replay keeps as_of in the fix-mapping form" do
    get root_path(as_of: "2017-06-12")
    assert_select ".banner.info", /Replay as of June 12, 2017/
    assert_select "details.fix input[name=as_of][value=?]", "2017-06-12"
  end
end
