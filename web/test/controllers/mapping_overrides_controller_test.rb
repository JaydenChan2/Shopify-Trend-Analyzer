require "test_helper"

class MappingOverridesControllerTest < ActionDispatch::IntegrationTest
  setup do
    MappingOverridesController.wikipedia_client = FakeWikipedia.new(resolve: {
      "Weighted blanket" => { title: "Weighted blanket", redirected_from: nil },
      "Air fryer" => { title: "Convection oven", redirected_from: "Air fryer" }
    }, missing: ["Not A Real Article"])
  end

  teardown do
    ENV.delete("DEMO_MODE")
    MappingOverridesController.wikipedia_client = nil
    MappingOverridesController.locked_without_password = false
    ENV.delete("OVERRIDES_PASSWORD")
  end

  test "saves an override for a real article and keeps as_of" do
    post mapping_overrides_path, params: { term: "Weighted Blanket", article: "Weighted blanket", as_of: "2017-06-12" }
    assert_redirected_to dashboard_path(as_of: "2017-06-12")
    assert_equal "Weighted blanket", MappingOverride.for_term("weighted blanket").article
    assert_match "now maps to", flash[:notice]
  end

  test "a redirect is saved as its target, and the merchant is told" do
    post mapping_overrides_path, params: { term: "Fryer", article: "Air fryer" }
    assert_equal "Convection oven", MappingOverride.for_term("fryer").article
    assert_match "redirects there", flash[:notice]
  end

  test "an article that doesn't exist is rejected and nothing is saved" do
    post mapping_overrides_path, params: { term: "Mug", article: "Not A Real Article" }
    assert_redirected_to dashboard_path
    assert_match "No Wikipedia article", flash[:alert]
    assert_equal 0, MappingOverride.count
  end

  test "don't track saves an ignored override" do
    post mapping_overrides_path, params: { term: "Gift Card", ignored: "1" }
    assert MappingOverride.for_term("gift card").ignored?
  end

  test "saving again updates the same override instead of duplicating it" do
    post mapping_overrides_path, params: { term: "Fryer", ignored: "1" }
    post mapping_overrides_path, params: { term: "fryer", article: "Weighted blanket" }
    assert_equal 1, MappingOverride.count
    refute MappingOverride.for_term("fryer").ignored?
  end

  test "public demo (production, no password): saving and removing are refused" do
    MappingOverridesController.locked_without_password = true
    override = MappingOverride.create!(term_key: "mug", ignored: true)

    post mapping_overrides_path, params: { term: "Gift Card", ignored: "1", as_of: "2017-06-12" }
    assert_redirected_to dashboard_path(as_of: "2017-06-12")
    assert_match "turned off", flash[:alert]

    delete mapping_overrides_path, params: { term: "mug" }
    assert_equal ["mug"], MappingOverride.pluck(:term_key)
  end

  test "with OVERRIDES_PASSWORD set, a wrong or missing password gets 401" do
    ENV["OVERRIDES_PASSWORD"] = "s3cret"
    post mapping_overrides_path, params: { term: "Gift Card", ignored: "1" }
    assert_response :unauthorized

    wrong = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "nope")
    post mapping_overrides_path, params: { term: "Gift Card", ignored: "1" }, headers: { "Authorization" => wrong }
    assert_response :unauthorized
    assert_equal 0, MappingOverride.count
  end

  test "with OVERRIDES_PASSWORD set, the right password works even when locked" do
    ENV["OVERRIDES_PASSWORD"] = "s3cret"
    MappingOverridesController.locked_without_password = true
    right = ActionController::HttpAuthentication::Basic.encode_credentials("admin", "s3cret")
    post mapping_overrides_path, params: { term: "Gift Card", ignored: "1" }, headers: { "Authorization" => right }
    assert_redirected_to dashboard_path
    assert MappingOverride.for_term("gift card").ignored?
  end

  test "remove deletes the override" do
    override = MappingOverride.create!(term_key: "mug", ignored: true)
    delete mapping_overrides_path, params: { term: "Mug", as_of: "2017-06-12" }
    assert_redirected_to dashboard_path(as_of: "2017-06-12")
    assert_equal 0, MappingOverride.count
  end

  # ---------- DEMO_MODE: per-visitor overrides ----------

  test "demo mode: a visitor's override is theirs alone and never touches the database" do
    ENV["DEMO_MODE"] = "true"
    MappingOverridesController.locked_without_password = true # production-like: still allowed in demo mode
    MappingOverride.create!(term_key: "matcha", article: "Matcha") # a seeded default

    alice = open_session
    bob = open_session
    alice.post mapping_overrides_path, params: { term: "Matcha", article: "Weighted blanket" }
    assert_match "Only you see this change", alice.flash[:notice]

    assert_equal "Matcha", MappingOverride.for_term("matcha").article, "the shared default is unchanged"
    assert_equal 1, MappingOverride.count
    assert_equal "Weighted blanket", alice.session["demo_overrides"]["matcha"]["article"]

    # What each visitor's dashboard shows (the demo catalog has a "Matcha" product).
    TrendsController.wikipedia_client = FakeWikipedia.new
    alice.get dashboard_path(inline: 1)
    bob.get dashboard_path(inline: 1)
    article = ->(visitor) { visitor.css_select(".product-card").find { |c| c.text.include?("Matcha") }.css(".article").text }
    assert_equal "Weighted blanket", article.(alice)
    assert_equal "Matcha", article.(bob)
  ensure
    TrendsController.wikipedia_client = nil
  end

  test "demo mode: removing a default hides it for that visitor only" do
    ENV["DEMO_MODE"] = "true"
    MappingOverride.create!(term_key: "giftcard", ignored: true)
    delete mapping_overrides_path, params: { term: "giftcard" }
    assert MappingOverride.for_term("giftcard"), "still there for everyone else"
    assert_nil OverrideSet.new(session: session).lookup("giftcard"), "gone for this visitor"
    assert OverrideSet.shared.lookup("giftcard").ignored
  end

  test "demo mode: removing your own change goes back to the shared default" do
    ENV["DEMO_MODE"] = "true"
    MappingOverride.create!(term_key: "matcha", article: "Matcha")
    post mapping_overrides_path, params: { term: "matcha", ignored: "1" }
    assert OverrideSet.new(session: session).lookup("matcha").ignored
    delete mapping_overrides_path, params: { term: "matcha" }
    entry = OverrideSet.new(session: session).lookup("matcha")
    assert_equal ["Matcha", :shared], [entry.article, entry.scope]
  end

  test "demo mode ignores OVERRIDES_PASSWORD: nothing shared can be changed anyway" do
    ENV["DEMO_MODE"] = "true"
    ENV["OVERRIDES_PASSWORD"] = "s3cret"
    post mapping_overrides_path, params: { term: "Gift Card", ignored: "1" }
    assert_redirected_to dashboard_path
    assert_equal 0, MappingOverride.count
  end
end
