require "csv"

# Articles that were standalone for a while and are redirects today, with the
# last date their own pageviews are valid. Read from backtest/trends.csv
# (`valid_until`), so the backtest and the app share one source of truth.
#
# Used for replays: on ?as_of=2017-12-31, "Air fryer" was still its own article,
# so we use its own views instead of today's redirect target (Convection oven).
module StandaloneHistory
  TRENDS_CSV = Rails.root.join("..", "backtest", "trends.csv")

  module_function

  # Date the article's own views stop being valid, or nil if not known.
  def valid_until(article)
    table[article]
  end

  def table
    @table ||= CSV.read(TRENDS_CSV, headers: true)
                  .select { |row| row["valid_until"].present? }
                  .to_h { |row| [row["article"], Date.iso8601(row["valid_until"])] }
  end
end
