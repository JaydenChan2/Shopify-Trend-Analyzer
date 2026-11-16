require "csv"

# The 16 trends the model was fitted on (backtest analysis "a"), by Wikipedia
# article. Used to flag hindsight checks that aren't a fair test: the model has
# already seen how these turned out.
module TrainingSet
  PREDICTIONS_CSV = Rails.root.join("..", "backtest", "results", "step_d_predictions.csv")

  module_function

  def include?(article)
    articles.include?(article)
  end

  # Trend names in the predictions file -> article titles via trends.csv.
  def articles
    @articles ||= begin
      names = CSV.read(PREDICTIONS_CSV, headers: true).select { |row| row["analysis"] == "a" }.map { |row| row["name"] }
      CSV.read(StandaloneHistory::TRENDS_CSV, headers: true).select { |row| names.include?(row["name"]) }
         .map { |row| row["article"] }.to_set
    end
  end
end
