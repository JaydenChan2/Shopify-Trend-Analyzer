require "test_helper"

class MappingOverrideTest < ActiveSupport::TestCase
  test "term is normalized so case and spacing don't create duplicates" do
    MappingOverride.create!(term_key: "  Air Fryer ", article: "Air fryer")
    assert_equal "air fryer", MappingOverride.last.term_key
    assert_equal "Air fryer", MappingOverride.for_term("AIR FRYER").article
    refute MappingOverride.new(term_key: "air fryer", article: "X").valid?
  end

  test "article is required unless the term is ignored" do
    refute MappingOverride.new(term_key: "mug").valid?
    assert MappingOverride.new(term_key: "mug", ignored: true).valid?
  end
end
