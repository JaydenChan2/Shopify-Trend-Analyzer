require "test_helper"

class TrendDetailTest < ActiveSupport::TestCase
  AS_OF = Date.new(2026, 11, 17)
  CUTOFF = LiveLabel.last_complete_week_end(AS_OF)
  # 40 quiet weeks, then a surge whose onset is 7 weeks before the cutoff: scored.
  SURGE = [1000] * 40 + [5000, 6000, 7000, 7500, 7000, 6800, 6500]

  def weeks(values, last_monday: CUTOFF - 6)
    values.each_with_index.map { |v, i| [last_monday - 7 * (values.size - 1 - i), v] }
  end

  test "a scored trend exposes onset, usual level, surge bar and features" do
    detail = TrendDetail.new("X", AS_OF, weeks(SURGE))
    assert detail.scored?
    assert_equal SURGE.size - 7, detail.onset_index
    assert_equal 1000, detail.baseline
    assert_equal 3000, detail.surge_bar
    assert_equal %w[growth acceleration peak_sharpness volatility], detail.contributions.map { |c| c[:name] }
  end

  test "contributions add up to the model's probability" do
    detail = TrendDetail.new("X", AS_OF, weeks(SURGE))
    model = TrendModel.instance
    logit = model.intercept + detail.contributions.sum { |c| c[:contribution] }
    assert_in_delta detail.probability, 1 / (1 + Math.exp(-logit)), 1e-12
  end

  # Same guarantee as the labels: the chart must not show weeks after as_of.
  test "weeks after as_of are dropped before anything is computed" do
    future = [[CUTOFF + 1, 9_999_999], [CUTOFF + 8, 9_999_999]]
    with_future = TrendDetail.new("X", AS_OF, weeks(SURGE) + future)
    without = TrendDetail.new("X", AS_OF, weeks(SURGE))
    assert_equal without.values, with_future.values
    assert_equal without.probability, with_future.probability
    refute_includes with_future.values, 9_999_999
  end

  test "no surge: usual level and surge bar come from the last 26 weeks" do
    detail = TrendDetail.new("X", AS_OF, weeks([4000] * 60))
    refute detail.scored?
    assert_nil detail.onset_index
    assert_equal 12_000, detail.surge_bar
  end

  test "empty series has no chart" do
    detail = TrendDetail.new("X", AS_OF, weeks([0] * 30))
    assert detail.empty?
    assert_nil detail.chart
  end
end
