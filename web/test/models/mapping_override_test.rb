require "test_helper"

class MappingOverrideTest < ActiveSupport::TestCase
  test "term is normalized so case and spacing don't create duplicates" do
    MappingOverride.create!(term_key: "  Air Fryer ", article: "Air fryer")
    assert_equal "air fryer", MappingOverride.last.term_key
    assert_equal "Air fryer", MappingOverride.for_term("AIR FRYER").article
    refute MappingOverride.new(term_key: "air fryer", article: "X").valid?
  end

  test "seeds are valid, idempotent and never overwrite a merchant's own fix" do
    MappingOverride.create!(term_key: "jellycat bashful bunny", ignored: true)
    2.times { load Rails.root.join("db/seeds.rb") }

    assert_equal "Crocs", MappingOverride.for_term("Crocs Jibbitz Charm Pack").article
    assert MappingOverride.for_term("giftcard").ignored?
    assert MappingOverride.for_term("jellycat bashful bunny").ignored?, "existing override was overwritten"
    assert_equal 7, MappingOverride.count
  end

  test "article is required unless the term is ignored" do
    refute MappingOverride.new(term_key: "mug").valid?
    assert MappingOverride.new(term_key: "mug", ignored: true).valid?
  end
end
