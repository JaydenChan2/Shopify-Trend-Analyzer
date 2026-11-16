class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  EARLIEST_AS_OF = Date.new(2016, 2, 1) # need ~26 weeks of data (from 2015-07) for a baseline

  private

  # ?as_of=YYYY-MM-DD for replays (dashboard and Discover).
  # Returns [date, error_message_or_nil]. Falls back to today on bad input.
  def parse_as_of(raw)
    return [Date.current, nil] if raw.blank?

    date = Date.iso8601(raw)
    if date > Date.current
      [Date.current, "as_of can't be in the future; showing today."]
    elsif date < EARLIEST_AS_OF
      [Date.current, "as_of must be on or after #{EARLIEST_AS_OF}; showing today."]
    else
      [date, nil]
    end
  rescue Date::Error
    [Date.current, "Couldn't read as_of=#{raw} (use YYYY-MM-DD); showing today."]
  end
end
