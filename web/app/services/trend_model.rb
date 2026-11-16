# The logistic regression exported by backtest/backtest.py (backtest/model.json).
# No Python at runtime: we apply the same formula by hand.
#
#   z_i = (x_i - mean_i) / scale_i
#   P(sustained) = 1 / (1 + e^-(intercept + sum(coef_i * z_i)))
class TrendModel
  DEFAULT_PATH = Rails.root.join("..", "backtest", "model.json")

  # Load once per process and reuse.
  def self.instance
    @instance ||= new(JSON.parse(File.read(ENV.fetch("MODEL_PATH", DEFAULT_PATH))))
  end

  attr_reader :features, :rules, :trained_on

  def initialize(data)
    @features     = data.fetch("features")
    @means        = data.fetch("scaler_mean")
    @scales       = data.fetch("scaler_scale")
    @coefficients = data.fetch("coefficients")
    @intercept    = data.fetch("intercept")
    @rules        = data.fetch("rules")
    @trained_on   = data.fetch("trained_on")
  end

  # feature_values: { "growth" => 0.4, ... } -> probability the trend is sustained
  def probability(feature_values)
    weighted_sum = @features.each_with_index.sum do |name, i|
      z = (feature_values.fetch(name) - @means[i]) / @scales[i]
      @coefficients[i] * z
    end
    1.0 / (1.0 + Math.exp(-(@intercept + weighted_sum)))
  end

  # Average value of a feature across the training trends (used to phrase reasons).
  def average(name)
    @means.fetch(@features.index(name))
  end
end
