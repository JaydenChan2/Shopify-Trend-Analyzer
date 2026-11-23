require "test_helper"

# The computed figures must match the backtest's own report
# (backtest/results/step_d_results.md): same counts, same Wilson intervals.
class BacktestStatsTest < ActiveSupport::TestCase
  REPORT = { # analysis => model => [correct, n, CI as in the report]
    a: { majority: [0, 16, "0–19%"], naive: [10, 16, "39–82%"], logreg: [12, 16, "51–90%"] },
    b: { majority: [4, 6, "30–90%"], naive: [3, 6, "19–81%"], logreg: [5, 6, "44–97%"] },
    c: { majority: [18, 25, "52–86%"], naive: [13, 25, "33–70%"], logreg: [22, 25, "70–96%"] },
    d: { majority: [13, 23, "37–74%"], naive: [13, 23, "37–74%"], logreg: [15, 23, "45–81%"] }
  }.freeze

  REPORT.each do |analysis, models|
    models.each do |model, (correct, n, ci)|
      test "analysis #{analysis} #{model}: #{correct}/#{n}, CI #{ci}" do
        assert_equal [correct, n], BacktestStats.score(analysis, model)
        assert_equal ci, BacktestStats.interval(analysis, model)
      end
    end
  end

  test "headline numbers, formatted" do
    assert_equal "62.5%", BacktestStats.percent(:a, :naive)
    assert_equal "75%", BacktestStats.percent(:a, :logreg)
    assert_equal "51–90%", BacktestStats.interval(:a, :logreg)
    assert_equal 16, BacktestStats.n
  end

  test "one decimal only when the value isn't whole" do
    assert_equal "66.7%", BacktestStats.format_percent(4, 6)
    assert_equal "50%", BacktestStats.format_percent(3, 6)
    assert_equal "0%", BacktestStats.format_percent(0, 16)
  end
end
