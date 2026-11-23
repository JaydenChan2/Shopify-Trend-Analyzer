require "test_helper"

class ShopifyClientTest < ActiveSupport::TestCase
  SECRET = "shpss_test_secret_do_not_leak".freeze

  # Fake HTTP: records calls, answers token and GraphQL requests from canned responses.
  class FakeHttp
    attr_reader :token_requests, :graphql_requests, :graphql_bodies

    def initialize(token_response: ["200", { "access_token" => "tok-1", "expires_in" => 86_400 }],
                   graphql_response: ["200", { "data" => { "products" => { "nodes" => [] } } }])
      @token_response, @graphql_response = token_response, graphql_response
      @token_requests, @graphql_requests, @graphql_bodies = [], [], []
    end

    def call(uri, body, headers)
      if uri.path.end_with?("/oauth/access_token")
        @token_requests << body
        @token_response
      else
        @graphql_requests << headers
        @graphql_bodies << body
        @graphql_response
      end
    end
  end

  def client(http, cache: ActiveSupport::Cache::MemoryStore.new)
    ShopifyClient.new(shop: "https://demo.myshopify.com/", client_id: "cid", client_secret: SECRET,
                      cache: cache, http: http)
  end

  test "requests a token with the client credentials grant" do
    http = FakeHttp.new
    assert_equal "tok-1", client(http).access_token
    assert_equal({ client_id: "cid", client_secret: SECRET, grant_type: "client_credentials" }, http.token_requests.first)
  end

  test "reuses a cached token until it is close to expiry, then refetches" do
    http = FakeHttp.new
    shopify = client(http)
    shopify.access_token
    travel 23.hours do
      shopify.access_token
      assert_equal 1, http.token_requests.size, "token should still be cached"
    end
    travel(24.hours - ShopifyClient::REFRESH_MARGIN + 1.second) do
      shopify.access_token
      assert_equal 2, http.token_requests.size, "token should be refetched near expiry"
    end
  end

  test "sends the token header and maps products" do
    nodes = [{ "id" => "gid://shopify/Product/1", "title" => "Air Fryer", "productType" => "Kitchen", "tags" => ["new"], "status" => "ACTIVE" },
             { "id" => "gid://shopify/Product/2", "title" => "Mug", "productType" => nil, "tags" => [], "status" => "ACTIVE" }]
    http = FakeHttp.new(graphql_response: ["200", { "data" => { "products" => { "nodes" => nodes } } }])
    products = client(http).products

    assert_equal "tok-1", http.graphql_requests.first["X-Shopify-Access-Token"]
    assert_equal({ id: "gid://shopify/Product/1", title: "Air Fryer", product_type: "Kitchen", tags: ["new"] }, products.first)
    assert_equal "", products.last[:product_type] # nil productType -> "" so the mapper falls back to title
  end

  # Fix 5: only active products, filtered in the query and again in code.
  test "asks for active products only and drops drafts and archived ones" do
    nodes = %w[ACTIVE DRAFT ARCHIVED].map.with_index do |status, i|
      { "id" => "gid://shopify/Product/#{i}", "title" => status, "productType" => "", "tags" => [], "status" => status }
    end
    http = FakeHttp.new(graphql_response: ["200", { "data" => { "products" => { "nodes" => nodes } } }])
    products = client(http).products

    assert_includes http.graphql_bodies.first[:query], 'query: "status:active"'
    assert_equal ["ACTIVE"], products.map { |p| p[:title] }
  end

  test "products are cached per shop for a few minutes, so dashboard views don't refetch" do
    http = FakeHttp.new
    shop = client(http)
    2.times { shop.products }
    assert_equal 1, http.graphql_requests.size
    travel ShopifyClient::PRODUCTS_TTL + 1.second do
      shop.products
    end
    assert_equal 2, http.graphql_requests.size, "refetched after the TTL"
  end

  test "a failed products fetch isn't cached" do
    cache = ActiveSupport::Cache::MemoryStore.new
    broken = FakeHttp.new(graphql_response: ["500", nil])
    assert_raises(ShopifyClient::Error) { client(broken, cache: cache).products }
    working = FakeHttp.new
    assert_equal [], client(working, cache: cache).products
    assert_equal 1, working.graphql_requests.size
  end

  test "GraphQL errors raise" do
    http = FakeHttp.new(graphql_response: ["200", { "errors" => [{ "message" => "Access denied for products field." }] }])
    error = assert_raises(ShopifyClient::Error) { client(http).products }
    assert_match "Access denied", error.message
  end

  test "token failure explains itself without leaking the secret" do
    http = FakeHttp.new(token_response: ["400", { "error" => "invalid_client" }])
    error = assert_raises(ShopifyClient::Error) { client(http).access_token }
    assert_match "invalid_client", error.message
    refute_includes error.message, SECRET
  end

  test "configured? needs all three env vars" do
    with_env("SHOPIFY_SHOP_DOMAIN" => "x.myshopify.com", "SHOPIFY_CLIENT_ID" => "id", "SHOPIFY_CLIENT_SECRET" => nil) do
      refute ShopifyClient.configured?
    end
    with_env("SHOPIFY_SHOP_DOMAIN" => "x.myshopify.com", "SHOPIFY_CLIENT_ID" => "id", "SHOPIFY_CLIENT_SECRET" => "s") do
      assert ShopifyClient.configured?
    end
  end

  private

  def with_env(vars)
    old = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end
