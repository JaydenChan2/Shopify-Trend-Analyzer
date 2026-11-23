class TrendsController < ApplicationController
  # Tests swap in fakes so they never call Wikipedia or Shopify.
  class_attribute :wikipedia_client, default: nil
  class_attribute :product_source, default: ProductSource

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
  def show
    load_as_of
    @product_title = params[:product].presence || params[:article]
    @detail = TrendDetail.build(params.require(:article), as_of: @as_of,
                                wikipedia: self.class.wikipedia_client || WikipediaClient.new)
    render layout: !request.xhr? # the dialog fetches just the panel
  rescue WikipediaClient::MissingContact, WikipediaClient::Error => e
    render plain: e.message, status: :bad_gateway
  end

  private

  def load_as_of
    @as_of, @as_of_error = parse_as_of(params[:as_of])
    @replay = params[:as_of].present? && @as_of_error.nil?
  end

  def load_rows
    @source = product_source.call
    wikipedia = self.class.wikipedia_client || WikipediaClient.new
    @rows = ProductTrend.rows(@source.products, as_of: @as_of, wikipedia: wikipedia, overrides: OverrideSet.for(session))
  rescue WikipediaClient::MissingContact => e
    @fatal_error = e.message
    @rows = []
  end
end
