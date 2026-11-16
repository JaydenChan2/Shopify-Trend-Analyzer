class TrendsController < ApplicationController
  EARLIEST_AS_OF = Date.new(2016, 2, 1) # need ~26 weeks of data (from 2015-07) for a baseline

  # GET /            -> labels as of today
  # GET /?as_of=DATE -> replay: what the app would have said on DATE (no data after it is used)
  def index
    @as_of, @as_of_error = parse_as_of(params[:as_of])
    @replay = params[:as_of].present? && @as_of_error.nil?
    @source = ProductSource.call
    wikipedia = WikipediaClient.new
    @rows = @source.products.map { |product| ProductTrend.call(product, as_of: @as_of, wikipedia: wikipedia) }
  rescue WikipediaClient::MissingContact => e
    @fatal_error = e.message
    @rows = []
  end

  private

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
