require "test_helper"

class TrendChartTest < ActiveSupport::TestCase
  AS_OF = Date.new(2026, 11, 17)
  CUTOFF = LiveLabel.last_complete_week_end(AS_OF)

  def chart_for(values)
    weeks = values.each_with_index.map { |v, i| [CUTOFF - 6 - 7 * (values.size - 1 - i), v] }
    TrendDetail.new("X", AS_OF, weeks).chart
  end

  test "shows the last two years and stays inside the drawing area" do
    chart = chart_for([1000] * 200 + [5000, 6000, 7000, 7500, 7000, 6800, 6500])
    points = chart.hover_points
    assert_equal TrendChart::WINDOW_WEEKS, points.size
    assert_in_delta TrendChart::PAD[:left], points.first[0], 0.1
    assert_in_delta TrendChart::WIDTH - TrendChart::PAD[:right], points.last[0], 0.1
    points.each { |x, y, _, _| assert y.between?(TrendChart::PAD[:top], chart.baseline_y), "y #{y} out of range" }
  end

  test "y axis covers the data and the surge bar" do
    chart = chart_for([500] * 60) # surge bar 1,500 and floor 2,000 are above the data
    assert chart.y_max >= 2000
  end

  test "onset and the shaded 6-week window are marked" do
    chart = chart_for([1000] * 60 + [5000, 6000, 7000, 7500, 7000, 6800, 6500])
    from, to = chart.feature_window
    assert_in_delta chart.onset_x, from, 0.01
    assert to > from
  end

  test "no onset means no onset marker or feature window" do
    chart = chart_for([3000] * 60)
    assert_nil chart.onset_x
    assert_nil chart.feature_window
  end

  test "compact view counts" do
    assert_equal "950", TrendChart.compact(950)
    assert_equal "12.5k", TrendChart.compact(12_500)
    assert_equal "2k", TrendChart.compact(2000)
    assert_equal "1.3M", TrendChart.compact(1_300_000)
  end
end
