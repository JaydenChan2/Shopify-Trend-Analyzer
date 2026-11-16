# Everything the trend panel shows for one article as of a date: the weekly
# series, the live label, and (when scored) the features and how each one pushed
# the model. Uses the same "complete weeks before as_of" cut-off as LiveLabel, so
# the chart can never show data the label couldn't see.
class TrendDetail
  attr_reader :article, :as_of, :mondays, :values, :result, :onset_index, :baseline,
              :features, :contributions, :probability

  def self.build(article, as_of:, wikipedia: WikipediaClient.new)
    cutoff = LiveLabel.last_complete_week_end(as_of)
    weeks = wikipedia.weekly_views(article, through: cutoff)
    new(article, as_of, weeks)
  end

  def initialize(article, as_of, weeks)
    cutoff = LiveLabel.last_complete_week_end(as_of)
    complete = weeks.select { |monday, _| monday + 6 <= cutoff }
    @article = article
    @as_of = as_of
    @mondays = complete.map(&:first)
    @values = complete.map(&:last)
    @result = LiveLabel.call(complete, as_of: as_of)
    @onset_index = @result.onset_week && @mondays.index(@result.onset_week)
    # "Usual level": the 26-week median before the onset, or before today if there's no surge.
    @baseline = TrendMath.baseline(@values, @onset_index || @values.length)
    score! if @result.confidence
  end

  def scored?
    !@features.nil?
  end

  # 3x the usual level: the bar a week has to clear to count as a surge.
  def surge_bar
    @baseline * TrendMath.rules["onset_multiplier"] if @baseline&.positive?
  end

  def floor
    TrendMath.rules["min_weekly_views"]
  end

  def empty?
    @values.empty? || @values.all?(&:zero?)
  end

  def chart
    TrendChart.new(self) unless empty?
  end

  private

  def score!
    model = TrendModel.instance
    @features = TrendMath.features(@values, @onset_index)
    @contributions = model.contributions(@features)
    @probability = model.probability(@features)
  end
end
