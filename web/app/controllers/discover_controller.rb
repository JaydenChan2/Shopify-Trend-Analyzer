# GET /discover            -> products surging on Wikipedia this week, store or not
# GET /discover?as_of=DATE -> replay: what Discover would have found on DATE
class DiscoverController < ApplicationController
  # Tests swap in fakes so they never call Wikipedia or Wikidata.
  class_attribute :wikipedia_client, default: nil
  class_attribute :wikidata_client, default: nil

  def index
    @as_of, @as_of_error = parse_as_of(params[:as_of])
    @replay = params[:as_of].present? && @as_of_error.nil?
    # Same answer for every as_of in the same week (and hindsight changes daily), so cache by both.
    key = ["discover-v1", LiveLabel.last_complete_week_end(@as_of), Date.current]
    @result = Rails.cache.fetch(key, expires_in: 12.hours) do
      TrendingProducts.call(as_of: @as_of, wikipedia: self.class.wikipedia_client || WikipediaClient.new,
                            wikidata: self.class.wikidata_client || WikidataClient.new)
    end
  rescue WikipediaClient::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    @error = e.message
  end
end
