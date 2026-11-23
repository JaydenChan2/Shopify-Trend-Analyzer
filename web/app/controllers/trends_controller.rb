class TrendsController < ApplicationController
  # Tests swap in fakes so they never call Wikipedia or Shopify.
  class_attribute :wikipedia_client, default: nil
  class_attribute :product_source, default: ProductSource

  # Each /trend view can mean Wikimedia API calls for a title from the URL: cap it per visitor (IP).
  rate_limit to: 60, within: 1.minute, only: :show, store: RATE_LIMIT_STORE,
             with: -> { trend_error(:too_many_requests, "Slow down a little", "Too many charts in a minute. Try again shortly.") }

  # GET /dashboard              -> page shell; app.js then loads the cards from /dashboard/cards
  # GET /dashboard?inline=1     -> the whole page with cards (no-JS fallback)
  # GET /dashboard?as_of=DATE   -> replay: what the app would have said on DATE (no data after it is used)
  def index
    load_as_of
    if params[:inline].present?
      load_rows
    else
      @source = product_source.describe # header pill only: no Shopify or Wikipedia calls
    end
  end

  # GET /dashboard/cards(?as_of=DATE) -> just the cards, for the shell to swap in
  def cards
    load_as_of
    load_rows
    render partial: "trends/results"
  end

  # GET /trend?article=Air+fryer&product=Air+Fryer&as_of=2017-12-31
  # The article comes from the URL, so it's validated, checked to exist (one cached title
  # lookup) before any pageviews are fetched, and rate limited per visitor.
  def show
    load_as_of
    article = params[:article].to_s.strip
    @product_title = params[:product].presence || article
    return trend_error(:bad_request, "No product picked", "This link is missing which Wikipedia article to chart.") if article.blank?
    unless WikipediaTitle.valid?(article)
      return trend_error(:bad_request, "That isn't a Wikipedia title",
                         "Titles are at most 255 characters and can't contain # < > [ ] { } or |.")
    end

    wikipedia = self.class.wikipedia_client || WikipediaClient.new
    if wikipedia.resolve_title(article).nil?
      return trend_error(:not_found, "No Wikipedia article called “#{article.truncate(80)}”",
                         "There's no article with that title, so there are no views to chart.")
    end

    @detail = TrendDetail.build(article, as_of: @as_of, wikipedia: wikipedia)
    render layout: !request.xhr? # the dialog fetches just the panel
  rescue WikipediaClient::MissingContact, WikipediaClient::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    trend_error(:bad_gateway, "Couldn't reach Wikipedia", "#{e.message}. Try again in a minute.")
  end

  private

  def load_as_of
    @as_of, @as_of_error = parse_as_of(params[:as_of])
    @replay = params[:as_of].present? && @as_of_error.nil?
  end

  def load_rows
    @source = product_source.call
    wikipedia = self.class.wikipedia_client || WikipediaClient.new
    @rows = DashboardRows.fetch(@source.products, as_of: @as_of, wikipedia: wikipedia, overrides: OverrideSet.for(session))
  rescue WikipediaClient::MissingContact => e
    @fatal_error = e.message
    @rows = []
  end

  # A friendly, in-app error (in the dialog for XHR, a full page otherwise).
  def trend_error(status, title, message)
    @error_title, @error_message = title, message
    render "trends/error", status: status, layout: !request.xhr?
  end
end
