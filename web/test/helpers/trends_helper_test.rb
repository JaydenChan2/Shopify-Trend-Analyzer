require "test_helper"

class TrendsHelperTest < ActionView::TestCase
  def row(label, confidence: nil, error: nil)
    ProductTrend::Row.new(products: [], mapping: nil, error: error,
                          result: error ? nil : LiveLabel::Result.new(label: label, confidence: confidence))
  end

  test "label tones" do
    assert_equal "success", label_tone("Likely sustained")
    assert_equal "warning", label_tone("Likely spike")
    assert_equal "caution", label_tone("Surge detected – too early to tell")
    assert_equal "neutral", label_tone("Not enough data")
    assert_equal "critical", label_tone("Error")
  end

  test "confidence is shown inside the label" do
    assert_equal "Likely sustained · 67%", label_text(row("Likely sustained", confidence: 0.672))
    assert_equal "No surge detected", label_text(row("No surge detected"))
    assert_equal "Error", label_text(row(nil, error: "timeout"))
  end

  test "summary counts group labels and only show errors when present" do
    rows = [row("Likely spike"), row("No surge detected"), row("No surge detected"), row("Not tracked")]
    assert_equal({ "surge" => ["Interest jumped", 1], "quiet" => ["No jump", 2], "nodata" => ["Not enough data", 0],
                   "unmapped" => ["Not mapped", 1] }, summary_counts(rows))
    assert_equal ["Errors", 1], summary_counts(rows + [row(nil, error: "x")])["error"]
  end

  test "every label belongs to one filter group" do
    assert_equal "surge", label_group("Possible surge (unconfirmed)")
    assert_equal "quiet", label_group("No surge detected")
    assert_equal "nodata", label_group("Not enough data")
    assert_equal "unmapped", label_group("Not tracked")
  end

  test "sparkline draws one point per week and skips empty series" do
    svg = sparkline([1, 2, 3, 4])
    assert_includes svg, "<polyline"
    assert_equal 4, svg[/polyline points="([^"]+)"/, 1].split.size
    assert_equal "", sparkline([0, 0, 0])
    assert_equal "", sparkline([])
  end
end
