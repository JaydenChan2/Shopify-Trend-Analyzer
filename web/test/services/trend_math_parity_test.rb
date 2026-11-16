require "test_helper"

# Python and Ruby must agree on onset, features and score for the same input.
# backtest/export_fixture.py writes the fixture from the Python code; this test
# runs every case through the Ruby port. Regenerate the fixture if the model changes.
class TrendMathParityTest < ActiveSupport::TestCase
  FIXTURE = JSON.parse(File.read(Rails.root.join("..", "backtest", "parity_fixture.json")))
  TOLERANCE = FIXTURE.fetch("tolerance")

  FIXTURE.fetch("cases").each do |c|
    test "parity: #{c['name']}" do
      values = c["values"]
      onset, rule = TrendMath.detect_onset(values)
      assert_same_or_nil c["onset"], onset, "onset index"
      assert_same_or_nil c["rule"], rule, "onset rule"
      next unless c["features"]

      ruby_features = TrendMath.features(values, onset)
      c["features"].each do |name, expected|
        if expected.nil?
          assert_nil ruby_features[name], name
        else
          assert_in_delta expected, ruby_features[name], TOLERANCE, name
        end
      end
      assert_in_delta c["probability"], TrendModel.instance.probability(ruby_features), TOLERANCE, "probability"
    end

    # The hindsight check's outcome label must match Python's label_from_onset.
    test "parity: outcome label: #{c['name']}" do
      onset, = TrendMath.detect_onset(c["values"])
      ruby = onset && Hindsight.label(c["values"], onset)
      if c["label"].nil?
        assert_nil ruby
      else
        label, peak, late_mean = ruby
        assert_equal c["label"], label
        assert_in_delta c["peak"], peak, TOLERANCE, "peak"
        assert_in_delta c["late_mean"], late_mean, TOLERANCE, "late mean"
      end
    end
  end

  # Minitest refuses assert_equal(nil, x); use assert_nil for the no-onset cases.
  def assert_same_or_nil(expected, actual, msg)
    expected.nil? ? assert_nil(actual, msg) : assert_equal(expected, actual, msg)
  end

  test "fixture covers both onset rules, no-onset and too-short cases" do
    cases = FIXTURE["cases"]
    assert cases.any? { |c| c["rule"] == "ratio" && c["probability"] }
    assert cases.any? { |c| c["rule"] == "fallback" && c["probability"] }
    assert cases.any? { |c| c["onset"].nil? }
    assert cases.any? { |c| c["onset"] && c["features"].nil? }
  end
end
