# Geometry for the trend panel's SVG chart (rendered in trends/_chart.html.erb).
# Plain math, no chart library: maps weeks to x and views to y, and works out
# reference lines, the onset marker, the shaded 6-week feature window and ticks.
class TrendChart
  WIDTH = 720
  HEIGHT = 260
  PAD = { left: 52, right: 14, top: 14, bottom: 30 }.freeze
  WINDOW_WEEKS = 104 # two years

  attr_reader :detail, :start

  def initialize(detail)
    @detail = detail
    n = detail.values.length
    @start = [n - WINDOW_WEEKS, 0].max
    # Replays can show an older onset: keep it in view with some context before it.
    @start = [[detail.onset_index - 26, 0].max, @start].min if detail.onset_index
  end

  def indices
    (@start...detail.values.length).to_a
  end

  def x(index)
    span = [indices.length - 1, 1].max
    PAD[:left] + (index - @start).to_f / span * (WIDTH - PAD[:left] - PAD[:right])
  end

  def y(views)
    PAD[:top] + (1 - views.to_f / y_max) * (HEIGHT - PAD[:top] - PAD[:bottom])
  end

  def baseline_y
    HEIGHT - PAD[:bottom]
  end

  # Top of the y-axis: a "nice" number above the data and both reference lines.
  def y_max
    @y_max ||= nice_ceiling([indices.map { |i| detail.values[i] }.max.to_i, detail.surge_bar.to_i, detail.floor].max * 1.08)
  end

  def line_points
    indices.map { |i| "#{x(i).round(1)},#{y(detail.values[i]).round(1)}" }.join(" ")
  end

  def area_points
    "#{x(@start).round(1)},#{baseline_y} #{line_points} #{x(indices.last).round(1)},#{baseline_y}"
  end

  # [x, y, "Week of Mar 6, 2017", views] per week, read by app.js for the hover tooltip.
  def hover_points
    indices.map do |i|
      [x(i).round(1), y(detail.values[i]).round(1), "Week of #{detail.mondays[i].strftime('%b %-d, %Y')}", detail.values[i]]
    end
  end

  def onset_x
    x(detail.onset_index) if detail.onset_index
  end

  # Shaded band over weeks 0-5 after onset: the only data the model's features read.
  def feature_window
    return nil unless detail.onset_index

    last = [detail.onset_index + TrendMath::EARLY_WEEKS - 1, detail.values.length - 1].min
    [x(detail.onset_index), x(last)]
  end

  def y_ticks
    (0..4).map { |k| y_max * k / 4 }
  end

  # A label at the start of each quarter, with the year on January.
  def x_ticks
    indices.each_cons(2).filter_map do |prev, i|
      month = detail.mondays[i].month
      next unless detail.mondays[prev].month != month && [1, 4, 7, 10].include?(month)

      [x(i), month == 1 ? detail.mondays[i].strftime("%Y") : detail.mondays[i].strftime("%b")]
    end
  end

  def self.compact(views)
    v = views.to_f
    if v >= 1_000_000 then "#{(v / 1_000_000).round(1).to_s.delete_suffix('.0')}M"
    elsif v >= 1000 then "#{(v / 1000).round(1).to_s.delete_suffix('.0')}k"
    else v.round.to_s
    end
  end

  private

  # Round up to 1, 2, 2.5 or 5 times a power of ten.
  def nice_ceiling(value)
    return 10 if value <= 0

    magnitude = 10**Math.log10(value).floor
    [1, 2, 2.5, 5, 10].map { |m| m * magnitude }.find { |candidate| candidate >= value }
  end
end
