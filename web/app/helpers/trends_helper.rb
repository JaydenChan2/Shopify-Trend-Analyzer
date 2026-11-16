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

  def label_tone(label)
    LABEL_TONES.fetch(label, "neutral")
  end

  def row_label(row)
    row.error ? "Error" : row.result.label
  end

  # "Likely sustained · 67%": confidence lives inside the label pill.
  def label_text(row)
    return "Error" if row.error

    confidence = row.result.confidence
    confidence ? "#{row.result.label} · #{number_to_percentage(confidence * 100, precision: 0)}" : row.result.label
  end

  # Counts for the stat cards, in display order. Errors only appear if there are any.
  def summary_counts(rows)
    labels = rows.map { |row| row_label(row) }
    counts = {
      "Surges" => labels.count { |l| SURGE_LABELS.include?(l) },
      "Quiet" => labels.count("No surge detected"),
      "Not enough data" => labels.count("Not enough data"),
      "Not mapped" => labels.count { |l| ["Not mapped", "Not tracked"].include?(l) }
    }
    errors = labels.count("Error")
    errors.positive? ? counts.merge("Errors" => errors) : counts
  end
end
