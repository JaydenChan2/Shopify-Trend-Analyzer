# GET /discover                -> page shell; app.js loads the results from /discover/results
# GET /discover?inline=1       -> the whole page with results (no-JS fallback)
# GET /discover?as_of=DATE     -> replay: what Discover would have found on DATE
class DiscoverController < ApplicationController
  # Tests swap in fakes so they never call Wikipedia or Wikidata.
  class_attribute :wikipedia_client, default: nil
  class_attribute :wikidata_client, default: nil

  def index
    load_as_of
    load_result if params[:inline].present?
  end

  # GET /discover/results(?as_of=DATE) -> just the results, for the shell to swap in
  def results
    load_as_of
    load_result
    render partial: "discover/results"
  end

  private

  def load_as_of
    @as_of, @as_of_error = parse_as_of(params[:as_of])
    @replay = params[:as_of].present? && @as_of_error.nil?
  end

  def load_result
    @result = DiscoverResults.fetch(@as_of, wikipedia: self.class.wikipedia_client || WikipediaClient.new,
                                            wikidata: self.class.wikidata_client || WikidataClient.new)
  rescue WikipediaClient::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    @error = e.message
  end
end
