require "test_helper"

class LiveLabelTest < ActiveSupport::TestCase
  FIRST_MONDAY = Date.new(2024, 1, 1)

  # Build [[monday, views], ...] from a list of weekly view counts.
  def weeks(values)
    values.each_with_index.map { |v, i| [FIRST_MONDAY + 7 * i, v] }
  end

  # as_of that makes exactly `n` weeks complete (Sunday of week n-1, plus the data lag).
  def as_of_after(n)
    FIRST_MONDAY + 7 * n - 1 + LiveLabel::DATA_LAG_DAYS
  end

  BASE = [1000] * 40

  test "last complete week ignores the current partial week and the data lag" do
    tuesday = Date.new(2026, 11, 17)
    assert_equal Date.new(2026, 11, 15), LiveLabel.last_complete_week_end(tuesday)
    monday = Date.new(2026, 11, 16) # Sunday's data isn't published yet
    assert_equal Date.new(2026, 11, 8), LiveLabel.last_complete_week_end(monday)
  end

  test "views that stopped entirely read as 'no views', not '~0 views/week'" do
    r = LiveLabel.call(weeks([3000] * 30 + [0] * 20), as_of: as_of_after(50))
    assert_equal "Not enough data", r.label
    assert_match "No Wikipedia views in recent weeks", r.reason
  end

  test "no surge when flat above the floor" do
    values = [3000] * 40
    assert_equal "No surge detected", LiveLabel.call(weeks(values), as_of: as_of_after(values.size)).label
  end

  # Fixes 4 and 6: every no-data case gets "Not enough data" with its own reason.
  test "not enough data when traffic is below the floor" do
    values = BASE # 1,000/week < 2,000 floor
    result = LiveLabel.call(weeks(values), as_of: as_of_after(values.size))
    assert_equal "Not enough data", result.label
    assert_match "~1,000 views/week", result.reason
  end

  test "not enough data when there are no views at all" do
    result = LiveLabel.call(weeks([0] * 40), as_of: as_of_after(40))
    assert_equal "Not enough data", result.label
    assert_match "No Wikipedia views", result.reason
  end

  test "not enough data when the article didn't exist yet at as_of" do
    values = [0] * 40 + [50_000] * 20 # created after week 40
    result = LiveLabel.call(weeks(values), as_of: as_of_after(30))
    assert_equal "Not enough data", result.label
    assert_match "may not have existed yet", result.reason
  end

  test "a surge that has faded below the floor is still scored, not 'not enough data'" do
    values = BASE + [5000, 6000, 3000, 1500, 1200, 1000, 900]
    assert_includes ["Likely sustained", "Likely spike"], LiveLabel.call(weeks(values), as_of: as_of_after(values.size)).label
  end

  test "possible surge when only the latest week is above the bar" do
    values = BASE + [5000]
    assert_equal "Possible surge (unconfirmed)", LiveLabel.call(weeks(values), as_of: as_of_after(values.size)).label
  end

  test "too early when confirmed but fewer than 6 weeks since onset" do
    values = BASE + [5000, 6000, 7000]
    result = LiveLabel.call(weeks(values), as_of: as_of_after(values.size))
    assert_equal "Surge detected – too early to tell", result.label
    assert_equal FIRST_MONDAY + 7 * 40, result.onset_week
    assert_match "3 of 6 weeks", result.reason
  end

  test "scored with a confidence once 6 weeks have passed" do
    values = BASE + [5000, 6000, 7000, 7500, 7000, 6800, 6500]
    result = LiveLabel.call(weeks(values), as_of: as_of_after(values.size))
    assert_includes ["Likely sustained", "Likely spike"], result.label
    assert result.confidence.between?(0.5, 1.0)
    assert_match "x its usual level", result.reason
  end

  test "a one-week blip is not a surge once the next week is in" do
    values = BASE + [20000, 1100]
    assert_equal "No surge detected", LiveLabel.call(weeks(values), as_of: as_of_after(values.size)).label
  end

  test "surge older than 10 weeks is outside the window" do
    values = BASE + [5000] * 12
    result = LiveLabel.call(weeks(values), as_of: as_of_after(values.size))
    assert_equal "No surge detected", result.label
    assert_match "older surge", result.reason
  end

  # The key no-lookahead guarantee for ?as_of=.
  test "data after as_of cannot change the label" do
    history = BASE + [5000, 6000, 7000, 7500, 7000, 6800, 6500]
    as_of = as_of_after(history.size)
    expected = LiveLabel.call(weeks(history), as_of: as_of)

    [[0] * 30, [9_999_999] * 30, [3000, 50, 800000]].each do |future|
      actual = LiveLabel.call(weeks(history + future), as_of: as_of)
      assert_equal expected.to_h, actual.to_h, "future data #{future.first(3)} changed the result"
    end
  end
end
