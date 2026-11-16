# Where products come from: the Shopify store if credentials are set, otherwise demo data.
module ProductSource
  Result = Struct.new(:products, :mode, :shop, :error, keyword_init: true)

  module_function

  def call
    return Result.new(products: DemoProducts::ALL, mode: :demo) unless ShopifyClient.configured?

    client = ShopifyClient.new
    Result.new(products: client.products, mode: :shopify, shop: client.shop)
  rescue ShopifyClient::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    # Credentials are set but something failed: show the error rather than silently
    # switching to demo data, which would hide a real configuration problem.
    Result.new(products: [], mode: :shopify, shop: client&.shop, error: e.message)
  end
end
