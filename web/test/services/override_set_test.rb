require "test_helper"

class OverrideSetTest < ActiveSupport::TestCase
  setup { MappingOverride.create!(term_key: "matcha", article: "Matcha", ignored: false) }

  test "visitor entries win over shared ones, and only in that session" do
    session = {}
    OverrideSet.new(session: session).save_for_visitor("Matcha", article: "Green tea")
    assert_equal "Green tea", OverrideSet.new(session: session).lookup("MATCHA").article
    assert_equal "Matcha", OverrideSet.shared.lookup("matcha").article
    assert_equal "Matcha", OverrideSet.new(session: {}).lookup("matcha").article
  end

  test "without DEMO_MODE, a request only sees shared overrides" do
    session = { OverrideSet::SESSION_KEY => { "matcha" => { "ignored" => true } } }
    refute OverrideSet.for(session).session_scoped?
    refute OverrideSet.for(session).lookup("matcha").ignored
  ensure
    ENV.delete("DEMO_MODE")
  end

  test "the session layer is capped so the cookie can't overflow" do
    session = {}
    set = OverrideSet.new(session: session)
    (OverrideSet::MAX_SESSION_ENTRIES + 5).times { |i| set.save_for_visitor("term #{i}", ignored: true) }
    assert_equal OverrideSet::MAX_SESSION_ENTRIES, session[OverrideSet::SESSION_KEY].size
    assert session[OverrideSet::SESSION_KEY].key?("term #{OverrideSet::MAX_SESSION_ENTRIES + 4}"), "newest kept"
  end

  test "the fingerprint changes when shared or visitor overrides change" do
    session = {}
    set = OverrideSet.new(session: session)
    before = set.fingerprint
    assert_equal before, OverrideSet.new(session: {}).fingerprint, "same overrides, same fingerprint"

    set.save_for_visitor("mug", ignored: true)
    refute_equal before, OverrideSet.new(session: session).fingerprint

    shared_before = OverrideSet.shared.fingerprint
    MappingOverride.create!(term_key: "scrunchie", ignored: true)
    refute_equal shared_before, OverrideSet.shared.fingerprint
  end
end
