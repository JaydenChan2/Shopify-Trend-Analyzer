require "test_helper"

class TrendsHelperTest < ActionView::TestCase
  test "label tones" do
    assert_equal "success", label_tone("Likely sustained")
    assert_equal "warning", label_tone("Likely spike")
    assert_equal "caution", label_tone("Surge detected – too early to tell")
    assert_equal "neutral", label_tone("Not enough data")
  end

  test "summary line counts each group and skips empty ones" do
    row = ->(label) { ProductTrend::Row.new(products: [], mapping: nil, result: LiveLabel::Result.new(label: label)) }
    rows = [row.("Likely spike"), row.("No surge detected"), row.("No surge detected"), row.("Not tracked")]
    assert_equal "1 surge · 2 quiet · 1 not mapped", summary_line(rows)
  end
end
