require "csv"

# The backtest's headline numbers, computed from its per-trend predictions
# (backtest/results/step_d_predictions.csv) instead of typed into views, so the
# homepage, FAQ, footer and methodology table can't drift apart.
#
# Analyses: "a" primary, "b" excluding articles created mid-trend, "c" 2x multiplier,
# "d" original 1-week rule. Models: "majority", "naive" ("still rising"), "logreg".
# Intervals are Wilson 95%, as in backtest/backtest.py (wilson_ci).
module BacktestStats
  PREDICTIONS_CSV = Rails.root.join("..", "backtest", "results", "step_d_predictions.csv")
  MODELS = %w[majority naive logreg].freeze
  Z = 1.96

  module_function

  # [correct, n] for one model in one analysis.
  def score(analysis, model)
    rows = by_analysis.fetch(analysis.to_s)
    [rows.count { |row| row[model.to_s] == row["label"] }, rows.size]
  end

  def n(analysis = :a)
    by_analysis.fetch(analysis.to_s).size
  end

  # "62.5%" / "75%": one decimal only when the value isn't whole.
  def percent(analysis, model)
    format_percent(*score(analysis, model))
  end

  # "51–90%" (Wilson 95%, whole percentages).
  def interval(analysis, model)
    low, high = wilson(*score(analysis, model))
    "#{(low * 100).round}–#{(high * 100).round}%"
  end

  def format_percent(correct, total)
    value = (100.0 * correct / total).round(1)
    value == value.round ? "#{value.round}%" : "#{value}%"
  end

  def wilson(correct, total)
    p = correct.to_f / total
    denom = 1 + Z**2 / total
    center = (p + Z**2 / (2 * total)) / denom
    half = Z * Math.sqrt(p * (1 - p) / total + Z**2 / (4 * total**2)) / denom
    [center - half, center + half]
  end

  def by_analysis
    @by_analysis ||= CSV.read(PREDICTIONS_CSV, headers: true).group_by { |row| row["analysis"] }
  end
end
