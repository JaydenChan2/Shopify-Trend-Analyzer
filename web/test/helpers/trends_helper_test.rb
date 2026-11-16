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
    assert_equal({ "Surges" => 1, "Quiet" => 2, "Not enough data" => 0, "Not mapped" => 1 }, summary_counts(rows))
    assert_equal 1, summary_counts(rows + [row(nil, error: "x")])["Errors"]
  end
end
