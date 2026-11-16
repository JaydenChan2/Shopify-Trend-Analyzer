# View helpers for the trends page (Polaris web components).
module TrendsHelper
  # Polaris <s-badge tone="..."> per label. Spikes are "warning", not "critical":
  # a spike isn't an error, just a reason to be careful with stock.
  LABEL_TONES = {
    "Likely sustained" => "success",
    "Likely spike" => "warning",
    "Surge detected – too early to tell" => "caution",
    "Possible surge (unconfirmed)" => "caution"
  }.freeze

  SURGE_LABELS = LABEL_TONES.keys.freeze

  def label_tone(label)
    LABEL_TONES.fetch(label, "neutral")
  end

  # "2 surges · 5 quiet · 4 not enough data · 3 not mapped" for the summary line.
  def summary_line(rows)
    labels = rows.map { |row| row.error ? "Error" : row.result.label }
    parts = {
      "surge" => labels.count { |l| SURGE_LABELS.include?(l) },
      "quiet" => labels.count("No surge detected"),
      "not enough data" => labels.count("Not enough data"),
      "not mapped" => labels.count { |l| ["Not mapped", "Not tracked"].include?(l) },
      "error" => labels.count("Error")
    }
    parts.reject { |_, n| n.zero? }.map do |name, n|
      name == "surge" ? pluralize(n, "surge") : "#{n} #{name}"
    end.join(" · ")
  end
end
