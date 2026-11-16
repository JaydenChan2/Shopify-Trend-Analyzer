# View helpers for the trends page.
module TrendsHelper
  # Colour tone per label (a CSS class suffix: .tone-success etc.).
  # Spikes are "warning", not "critical": a spike isn't an error, just a reason
  # to be careful with stock.
  LABEL_TONES = {
    "Likely sustained" => "success",
    "Likely spike" => "warning",
    "Surge detected – too early to tell" => "caution",
    "Possible surge (unconfirmed)" => "caution",
    "Error" => "critical"
  }.freeze

  SURGE_LABELS = LABEL_TONES.keys.first(4).freeze

  # Stat cards double as filters: each label belongs to one group.
  GROUPS = {
    "surge" => "Interest jumped", "quiet" => "No jump", "nodata" => "Not enough data",
    "unmapped" => "Not mapped", "error" => "Errors"
  }.freeze

  FEATURE_NAMES = {
    "growth" => ["Growth", "are the later weeks higher than the first ones?"],
    "acceleration" => ["Speeding up", "is growth getting faster or slower?"],
    "peak_sharpness" => ["Sharp peak", "is it one big spike or a steady climb?"],
    "volatility" => ["Jumpiness", "how much it swings week to week"]
  }.freeze

  def label_tone(label)
    LABEL_TONES.fetch(label, "neutral")
  end

  def row_label(row)
    row.error ? "Error" : row.result.label
  end

  def label_group(label)
    case label
    when *SURGE_LABELS then "surge"
    when "No surge detected" then "quiet"
    when "Not enough data" then "nodata"
    when "Error" then "error"
    else "unmapped"
    end
  end

  # "Likely sustained · 67%": confidence lives inside the label pill.
  def label_text(row)
    return "Error" if row.error

    confidence = row.result.confidence
    confidence ? "#{row.result.label} · #{percent(confidence)}" : row.result.label
  end

  def percent(fraction)
    number_to_percentage(fraction * 100, precision: 0)
  end

  # { "surge" => ["Surges", 2], ... } for the stat cards. Errors only appear if there are any.
  def summary_counts(rows)
    groups = rows.map { |row| label_group(row_label(row)) }
    GROUPS.filter_map do |key, name|
      count = groups.count(key)
      [key, [name, count]] unless key == "error" && count.zero?
    end.to_h
  end

  # Tiny inline SVG of recent weekly views for a card.
  def sparkline(values, width: 240, height: 44)
    return "" if values.blank? || values.max.to_i.zero? || values.size < 2

    max = values.max.to_f
    step = width.to_f / (values.size - 1)
    points = values.each_with_index.map { |v, i| "#{(i * step).round(1)},#{(height - 3 - v / max * (height - 6)).round(1)}" }
    tag.svg(class: "sparkline", viewBox: "0 0 #{width} #{height}", preserveAspectRatio: "none", "aria-hidden": true) do
      tag.polygon(points: "0,#{height} #{points.join(' ')} #{width},#{height}", class: "spark-area") +
        tag.polyline(points: points.join(" "), class: "spark-line")
    end
  end

  def compact_views(views)
    TrendChart.compact(views)
  end
end
