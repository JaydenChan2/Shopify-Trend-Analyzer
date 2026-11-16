require "net/http"

# Reads products from a dev store through a Dev Dashboard app (same org as the store).
#
# Auth: client credentials grant. POST client_id + client_secret to
# https://{shop}/admin/oauth/access_token and get a token that expires after
# ~24h. We cache it with its expiry and fetch a new one shortly before it lapses.
#
# The client secret is only ever sent in that POST body: it's never logged,
# put in an error message, or cached.
class ShopifyClient
  class Error < StandardError; end

  API_VERSION = "2026-10".freeze
  REFRESH_MARGIN = 5.minutes # refetch when the token has less than this left
  ENV_VARS = %w[SHOPIFY_SHOP_DOMAIN SHOPIFY_CLIENT_ID SHOPIFY_CLIENT_SECRET].freeze

  # Only ACTIVE products: archived and draft ones aren't for sale.
  PRODUCTS_QUERY = <<~GRAPHQL.freeze
    query Products($first: Int!) {
      products(first: $first, sortKey: TITLE, query: "status:active") {
        nodes { id title productType tags status }
      }
    }
  GRAPHQL

  def self.configured?
    ENV_VARS.all? { |name| ENV[name].present? }
  end

  # http: callable (uri, body_hash, headers) -> [status_code_string, parsed_json_or_nil]
  def initialize(shop: ENV["SHOPIFY_SHOP_DOMAIN"], client_id: ENV["SHOPIFY_CLIENT_ID"],
                 client_secret: ENV["SHOPIFY_CLIENT_SECRET"], cache: Rails.cache, http: method(:post_json))
    @shop = shop.to_s.sub(%r{\Ahttps?://}, "").chomp("/")
    @client_id = client_id
    @client_secret = client_secret
    @cache = cache
    @http = http
  end

  attr_reader :shop

  # [{ id:, title:, product_type:, tags: }, ...]
  # TODO(pagination): only the first 50 products for v0; follow pageInfo.endCursor for more.
  def products(limit: 50)
    status, body = @http.call(URI("https://#{@shop}/admin/api/#{API_VERSION}/graphql.json"),
                              { query: PRODUCTS_QUERY, variables: { first: limit } },
                              { "X-Shopify-Access-Token" => access_token })
    raise Error, "Shopify GraphQL returned HTTP #{status}" unless status == "200"
    raise Error, "Shopify GraphQL error: #{body['errors'].map { |e| e['message'] }.join('; ')}" if body["errors"]

    nodes = body.dig("data", "products", "nodes")
    nodes.select { |node| node["status"] == "ACTIVE" }.map do |node| # belt and braces on top of the query filter
      { id: node["id"], title: node["title"], product_type: node["productType"].to_s, tags: node["tags"] }
    end
  end

  def access_token
    cached = @cache.read(token_cache_key)
    return cached[:token] if cached && cached[:expires_at] > Time.current + REFRESH_MARGIN

    fetch_new_token
  end

  private

  def fetch_new_token
    status, body = @http.call(URI("https://#{@shop}/admin/oauth/access_token"),
                              { client_id: @client_id, client_secret: @client_secret,
                                grant_type: "client_credentials" },
                              {})
    unless status == "200" && body&.dig("access_token")
      detail = body.is_a?(Hash) ? (body["error_description"] || body["error"] || body["errors"]) : nil
      raise Error, "Couldn't get a Shopify access token (HTTP #{status}#{": #{detail}" if detail}). " \
                   "Check the app is installed on #{@shop} and has read_products."
    end

    expires_in = body.fetch("expires_in", 86_400).to_i
    @cache.write(token_cache_key, { token: body["access_token"], expires_at: Time.current + expires_in },
                 expires_in: expires_in)
    body["access_token"]
  end

  def token_cache_key
    ["shopify-token-v1", @shop, @client_id]
  end

  def post_json(uri, body, headers)
    request = Net::HTTP::Post.new(uri, { "Content-Type" => "application/json", "Accept" => "application/json" }.merge(headers))
    request.body = body.to_json
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
      http.request(request)
    end
    parsed = begin
      JSON.parse(response.body)
    rescue JSON::ParserError, TypeError
      nil
    end
    [response.code, parsed]
  end
end
