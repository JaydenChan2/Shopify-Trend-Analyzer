# Turns a weekly pageview series into one of four live labels plus a reason.
#
#   "Possible surge (unconfirmed)"        latest week meets the onset condition, no 2nd week yet
#   "Surge detected – too early to tell"  onset confirmed but weeks 0-5 aren't all complete
#   "Likely sustained" / "Likely spike"   onset 6-10 weeks ago: scored by the model
#   "No surge detected"                   no onset started in the last 10 weeks
#   "Not enough data"                     no views, or traffic below the floor (and no recent surge)
#
# Zero lookahead: everything after the last complete week before `as_of` is
# dropped before any logic runs (see test/services/live_label_test.rb).
class LiveLabel
  LIVE_WINDOW_WEEKS = 10
  DATA_LAG_DAYS = 2 # Wikipedia publishes a day late; a week counts once its Sunday is 2+ days old

  Result = Struct.new(:label, :confidence, :reason, :onset_week, keyword_init: true)

  # Latest Sunday that's at least DATA_LAG_DAYS before as_of.
  def self.last_complete_week_end(as_of)
    day = as_of - DATA_LAG_DAYS
    day - day.wday # Date#wday: Sunday = 0
  end

  # weeks: [[monday_date, views], ...] sorted oldest first.
  def self.call(weeks, as_of:)
    cutoff = last_complete_week_end(as_of)
    complete = weeks.select { |monday, _| monday + 6 <= cutoff }
    new(complete).result
  end

  def initialize(weeks)
    @mondays = weeks.map(&:first)
    @values = weeks.map(&:last)
    @first_week = @values.index(&:positive?)
    @confirm = TrendMath.rules["onset_confirm_weeks"]
  end

  def result
    if @first_week.nil?
      return not_enough_data("No Wikipedia views up to this date (the article may not have existed yet, or had a different title).")
    end

    onset, confirmed = find_recent_onset
    return quiet_result if onset.nil?
    return possible_surge(onset) unless confirmed

    weeks_since = @values.length - onset
    weeks_since < TrendMath::EARLY_WEEKS ? too_early(onset, weeks_since) : scored(onset)
  end

  private

  # Earliest week in the last 10 that starts a surge. Returns [index, confirmed?] or [nil, nil].
  def find_recent_onset
    n = @values.length
    ([n - LIVE_WINDOW_WEEKS, 0].max...n).each do |t|
      next if surging?(t - 1) # the previous week was already surging: not a new onset

      return [t, true] if TrendMath.surge_rule(@values, t, @first_week, weeks: @confirm)
      # Too close to the end for a 2nd week: is everything we do have above the bar?
      return [t, false] if t + @confirm > n && TrendMath.surge_rule(@values, t, @first_week, weeks: n - t)
    end
    [nil, nil]
  end

  def surging?(t)
    TrendMath.surge_rule(@values, t, @first_week, weeks: 1)
  end

  # ---------- the four states ----------

  def scored(onset)
    features = TrendMath.features(@values, onset)
    p = TrendModel.instance.probability(features)
    sustained = p >= 0.5
    Result.new(label: sustained ? "Likely sustained" : "Likely spike",
               confidence: sustained ? p : 1 - p,
               reason: scored_reason(onset, features),
               onset_week: @mondays[onset])
  end

  def too_early(onset, weeks_since)
    Result.new(label: "Surge detected – too early to tell", onset_week: @mondays[onset],
               reason: "#{level_phrase(onset, @values[onset..].max)}; " \
                       "#{weeks_since} of #{TrendMath::EARLY_WEEKS} weeks of data needed for a call.".upcase_first)
  end

  def possible_surge(onset)
    Result.new(label: "Possible surge (unconfirmed)", onset_week: @mondays[onset],
               reason: "#{level_phrase(onset, @values[onset])} last week; " \
                       "needs a second week above the bar to confirm.".upcase_first)
  end

  def no_surge(reason)
    Result.new(label: "No surge detected", reason: reason)
  end

  def not_enough_data(reason)
    Result.new(label: "Not enough data", reason: reason)
  end

  # No onset in the window: still elevated from an older surge, too little traffic, or steady.
  def quiet_result
    recent = TrendMath.mean(@values.last(4))
    floor = TrendMath.rules["min_weekly_views"]
    if surging?(@values.length - 1)
      no_surge("Elevated for over #{LIVE_WINDOW_WEEKS} weeks (an older surge, outside the window).")
    elsif recent < 1
      not_enough_data("No Wikipedia views in recent weeks (the article may have been renamed, merged or deleted).")
    elsif recent < floor
      not_enough_data("Only ~#{fmt_views(recent)} views/week recently; a surge needs at least " \
                      "#{fmt_views(floor)}/week to be detected.")
    else
      no_surge("Steady around #{fmt_views(recent)} views/week; no 3x jump in the last #{LIVE_WINDOW_WEEKS} weeks.")
    end
  end

  # ---------- reasons ----------

  def scored_reason(onset, f)
    early = @values[onset, TrendMath::EARLY_WEEKS]
    model = TrendModel.instance
    parts = [level_phrase(onset, TrendMath.mean(early)) + " over 6 weeks", direction_phrase(f)]
    parts << "sharper early peak than typical trends" if f["peak_sharpness"] > model.average("peak_sharpness")
    parts << "jumpy week to week" if f["volatility"] > model.average("volatility")
    parts.join(", ").upcase_first + "."
  end

  # "Interest 3.4x its usual level" or, for brand-new articles, "New article at ~5,000 views/week".
  def level_phrase(onset, views)
    usual = TrendMath.baseline(@values, onset)
    if usual&.positive? && onset - @first_week >= TrendMath.rules["baseline_weeks"]
      "interest #{format('%.1f', views / usual)}x its usual level"
    else
      "new article at ~#{fmt_views(views)} views/week"
    end
  end

  def direction_phrase(f)
    growth, accel = f["growth"], f["acceleration"]
    if growth > 0.1
      accel < -0.1 ? "still climbing but slowing" : (accel > 0.1 ? "climbing faster" : "still climbing")
    elsif growth < -0.1
      accel > 0.1 ? "fading, but the drop is easing" : "fading from its early peak"
    else
      "holding steady"
    end
  end

  def fmt_views(x)
    x.round.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
  end
end
