# Where products come from: the Shopify store if credentials are set, otherwise demo data.
module ProductSource
  module_function

  # Returns [products, mode] where mode is :shopify or :demo.
  def call
    # Phase 2b wires up ShopifyClient here.
    [DemoProducts::ALL, :demo]
  end
end
