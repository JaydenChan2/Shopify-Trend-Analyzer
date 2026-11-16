# Did a replayed call come true? Applies the backtest's label rule
# (backtest/series.py label_from_onset) to the year after the surge started:
#
#   sustained if mean views in weeks 26-51 after onset >= 25% of the peak week in weeks 0-25
#
# This deliberately looks past `as_of`: it's the answer key, shown next to the
# call, never fed into it. The call itself still only sees data before `as_of`.
#
# status:
#   :checked      a full year has passed; outcome is "sustained" or "spike"
#   :pending      not a year yet; ready_on says when
#   :unavailable  the article stopped being standalone before the year was up
# came_true: true/false for "Likely sustained/spike" calls, nil for other labels
# in_training: the model was fitted on this trend, so it isn't a fair test
class Hindsight
  PEAK_WEEKS = 26     # backtest/series.py LABEL_PEAK_WEEKS
  LATE_END = 52       # backtest/series.py LABEL_LATE_END
  SUSTAIN_RATIO = 0.25 # backtest/series.py SUSTAIN_RATIO

  CALLS = { "Likely sustained" => "sustained", "Likely spike" => "spike" }.freeze

  Result = Struct.new(:status, :outcome, :peak, :late_mean, :ready_on, :came_true, :in_training,
                      keyword_init: true) do
    def ratio
      late_mean / peak if peak&.positive?
    end
  end

  # Pure rule on a values array (parity-tested against Python). nil without a full year.
  def self.label(values, onset)
    return nil if onset + LATE_END > values.length

    peak = values[onset, PEAK_WEEKS].max.to_f
    late_mean = TrendMath.mean(values[(onset + PEAK_WEEKS)...(onset + LATE_END)])
    [late_mean >= SUSTAIN_RATIO * peak ? "sustained" : "spike", peak, late_mean]
  end

  # article: whose views the call used; result: the LiveLabel::Result of the replay.
  # Returns nil when there's nothing to check (no surge in the call).
  def self.call(article:, result:, wikipedia:, today: Date.current)
    onset_week = result&.onset_week or return nil

    in_training = TrainingSet.include?(article)
    year_end = onset_week + LATE_END * 7 - 1 # Sunday ending week 51
    cutoff = LiveLabel.last_complete_week_end(today)
    if year_end > cutoff
      return Result.new(status: :pending, ready_on: year_end + LiveLabel::DATA_LAG_DAYS, in_training: in_training)
    end

    valid_until = StandaloneHistory.valid_until(article)
    return Result.new(status: :unavailable, in_training: in_training) if valid_until && year_end > valid_until

    weeks = wikipedia.weekly_views(article, through: cutoff)
    onset = weeks.index { |monday, _| monday == onset_week }
    outcome, peak, late_mean = label(weeks.map(&:last), onset)
    Result.new(status: :checked, outcome: outcome, peak: peak, late_mean: late_mean, in_training: in_training,
               came_true: CALLS.key?(result.label) ? CALLS[result.label] == outcome : nil)
  end
end
