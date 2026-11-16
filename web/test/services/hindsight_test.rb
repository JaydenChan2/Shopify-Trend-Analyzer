require "test_helper"

class HindsightTest < ActiveSupport::TestCase
  ONSET = Date.new(2020, 1, 6) # a Monday
  TODAY = Date.new(2026, 11, 16)

  # 1,000/week, then from ONSET: 26 weeks peaking at 20,000, then 26 weeks at `late`.
  class SurgeWiki
    def initialize(late) = @late = late

    def weekly_views(_article, through:)
      mondays = (WikipediaClient::FIRST_MONDAY..through).step(7).select { |m| m + 6 <= through }
      mondays.map do |m|
        weeks_in = ((m - ONSET) / 7).to_i
        views = if weeks_in.negative? || weeks_in >= 52 then 1000
                elsif weeks_in < 26 then weeks_in.zero? ? 20_000 : 8000
                else @late
                end
        [m, views]
      end
    end
  end

  def call(label, late:, article: "Pop Mart", onset: ONSET, today: TODAY)
    result = LiveLabel::Result.new(label: label, onset_week: onset)
    Hindsight.call(article: article, result: result, wikipedia: SurgeWiki.new(late), today: today)
  end

  test "the rule: late average vs 25% of the early peak" do
    assert_equal ["sustained", 100.0, 25.0], Hindsight.label([100] + [10] * 25 + [25] * 26, 0)
    assert_equal "spike", Hindsight.label([100] + [10] * 25 + [24] * 26, 0).first
    assert_nil Hindsight.label([100] * 51, 0), "needs 52 weeks"
  end

  test "a sustained call that lasted came true" do
    h = call("Likely sustained", late: 6000)
    assert_equal :checked, h.status
    assert_equal "sustained", h.outcome
    assert_in_delta 0.3, h.ratio, 1e-9
    assert h.came_true
  end

  test "a spike call on a trend that lasted is a miss" do
    h = call("Likely spike", late: 6000)
    refute h.came_true
    assert_equal false, h.came_true
  end

  test "a spike call on a trend that faded came true" do
    h = call("Likely spike", late: 2000)
    assert_equal "spike", h.outcome
    assert h.came_true
  end

  test "too-early labels get the outcome but no verdict" do
    h = call("Surge detected – too early to tell", late: 2000)
    assert_equal "spike", h.outcome
    assert_nil h.came_true
  end

  test "pending until a full year of complete weeks exists" do
    h = call("Likely sustained", late: 6000, onset: Date.new(2026, 3, 2))
    assert_equal :pending, h.status
    assert_equal Date.new(2027, 3, 2), h.ready_on # Sunday ending week 51 (Feb 28) + 2 days' data lag
  end

  test "unavailable when the article was merged before the year was up" do
    # Air fryer's own views are only valid until 2023-05-04 (backtest/trends.csv).
    h = call("Likely sustained", late: 6000, article: "Air fryer", onset: Date.new(2023, 1, 2))
    assert_equal :unavailable, h.status
    assert_equal :checked, call("Likely sustained", late: 6000, article: "Air fryer").status
  end

  test "no surge in the call means nothing to check" do
    assert_nil Hindsight.call(article: "Pop Mart", result: LiveLabel::Result.new(label: "No surge detected"),
                              wikipedia: SurgeWiki.new(0), today: TODAY)
  end

  test "trends the model was trained on are flagged" do
    assert call("Likely spike", late: 2000, article: "Fidget spinner").in_training
    assert call("Likely sustained", late: 6000, article: "Labubu").in_training
    refute call("Likely sustained", late: 6000, article: "Pop Mart").in_training
    assert_equal 16, TrainingSet.articles.size
  end
end
