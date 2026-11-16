class TrendsController < ApplicationController
  # Tests swap in a fake so they never call Wikipedia.
  class_attribute :wikipedia_client, default: nil

  # GET /            -> labels as of today
  # GET /?as_of=DATE -> replay: what the app would have said on DATE (no data after it is used)
  def index
    @as_of, @as_of_error = parse_as_of(params[:as_of])
    @replay = params[:as_of].present? && @as_of_error.nil?
    @source = ProductSource.call
    wikipedia = self.class.wikipedia_client || WikipediaClient.new
    @rows = ProductTrend.rows(@source.products, as_of: @as_of, wikipedia: wikipedia)
  rescue WikipediaClient::MissingContact => e
    @fatal_error = e.message
    @rows = []
  end

  # GET /trend?article=Air+fryer&product=Air+Fryer&as_of=2017-12-31
  def show
    @as_of, @as_of_error = parse_as_of(params[:as_of])
    @replay = params[:as_of].present? && @as_of_error.nil?
    @product_title = params[:product].presence || params[:article]
    @detail = TrendDetail.build(params.require(:article), as_of: @as_of,
                                wikipedia: self.class.wikipedia_client || WikipediaClient.new)
    render layout: !request.xhr? # the dialog fetches just the panel
  rescue WikipediaClient::MissingContact, WikipediaClient::Error => e
    render plain: e.message, status: :bad_gateway
  end
end
