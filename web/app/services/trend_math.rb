# Ruby port of backtest/series.py (detect_onset) and backtest/features.py.
# Must match Python to 1e-9: see test/services/trend_math_parity_test.rb.
# Rules (multiplier, floor, ...) come from model.json so there's one source of truth.
module TrendMath
  EARLY_WEEKS = 6

  module_function

  def rules
    TrendModel.instance.rules
  end

  # Python: series.detect_onset. First week t (searching from `from`) where the
  # surge condition holds for `confirm_weeks` weeks. Returns [t, "ratio"|"fallback"] or [nil, nil].
  def detect_onset(values, from: 0, multiplier: rules["onset_multiplier"], confirm_weeks: rules["onset_confirm_weeks"])
    first_week = values.index { |v| v > 0 }
    return [nil, nil] if first_week.nil?

    (from..(values.length - confirm_weeks)).each do |t|
      rule = surge_rule(values, t, first_week, weeks: confirm_weeks, multiplier: multiplier)
      return [t, rule] if rule
    end
    [nil, nil]
  end

  # Does the surge condition hold in weeks t...t+weeks, all judged against the
  # baseline before week t? Returns "ratio", "fallback" or nil.
  #   ratio:    view count > multiplier x median(previous 26 weeks) and >= floor
  #   fallback: article created after data start and still in its first 26 weeks: >= floor
  def surge_rule(values, t, first_week, weeks:, multiplier: rules["onset_multiplier"])
    return nil if t.negative? || t + weeks > values.length

    window = values[t, weeks]
    floor = rules["min_weekly_views"]
    history = t - first_week

    if history >= rules["baseline_weeks"]
      threshold = multiplier * baseline(values, t)
      "ratio" if window.all? { |v| v > threshold && v >= floor }
    elsif first_week.positive? && history >= 0
      "fallback" if window.all? { |v| v >= floor }
    end
  end

  # Median of the 26 weeks before week t (nil if there aren't 26).
  def baseline(values, t)
    n = rules["baseline_weeks"]
    return nil if t < n

    median(values[(t - n)...t])
  end

  # Python: features.compute_features. Reads ONLY weeks onset..onset+5.
  def features(values, onset)
    v = values[onset, EARLY_WEEKS]&.map(&:to_f)
    raise ArgumentError, "need #{EARLY_WEEKS} complete weeks after onset" if v.nil? || v.length < EARLY_WEEKS

    log_changes = (1...EARLY_WEEKS).map { |i| Math.log((v[i] + 1) / (v[i - 1] + 1)) }
    {
      "growth"         => Math.log((mean(v[3..5]) + 1) / (mean(v[0..2]) + 1)),
      "acceleration"   => Math.log((v[5] + 1) / (v[3] + 1)) - Math.log((v[2] + 1) / (v[0] + 1)),
      "peak_sharpness" => v.max / mean(v),
      "volatility"     => population_std(log_changes),
      "yoy_ratio"      => yoy_ratio(values, onset, v)
    }
  end

  # Same 6 weeks one year earlier (past data, so not lookahead). nil if unavailable.
  def yoy_ratio(values, onset, early)
    start = onset - 52
    return nil if start.negative?

    prior = values[start, EARLY_WEEKS].map(&:to_f)
    mean(prior).positive? ? mean(early) / mean(prior) : nil
  end

  def mean(xs)
    xs.sum.to_f / xs.length
  end

  # numpy's default np.std (ddof=0).
  def population_std(xs)
    m = mean(xs)
    Math.sqrt(xs.sum { |x| (x - m)**2 } / xs.length)
  end

  # numpy's np.median: average the two middle values when the count is even.
  def median(xs)
    sorted = xs.sort
    mid = sorted.length / 2
    sorted.length.odd? ? sorted[mid].to_f : (sorted[mid - 1] + sorted[mid]) / 2.0
  end
end
