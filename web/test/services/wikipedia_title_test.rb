require "test_helper"

class WikipediaTitleTest < ActiveSupport::TestCase
  test "real titles pass" do
    ["Fidget spinner", "M&M's", "Pokémon Trading Card Game", "Stanley (drinkware company)", "C++", "AC/DC"].each do |t|
      assert WikipediaTitle.valid?(t), t
    end
  end

  test "empty, too long or forbidden characters fail" do
    ["", "   ", "a" * 256, "é" * 128, "Bad|Title", "A#section", "<script>", "a[b]", "{x}", "tab\there"].each do |t|
      refute WikipediaTitle.valid?(t), t.inspect
    end
  end
end
