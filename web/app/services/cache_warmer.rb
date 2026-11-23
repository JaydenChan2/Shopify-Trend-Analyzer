# Pre-fetches what a visitor's first page view would otherwise wait for: the
# store's Wikipedia series (today and the README replays) and Discover.
#
# Runs once in a background thread when the server boots (config/initializers/
# cache_warmer.rb). On Render's free plan the instance sleeps after 15 minutes
# and its disk (the cache) is wiped, so every wake-up starts cold: warming at boot
# means the cache is filling while the visitor who woke it is still on the landing page.
#
# Uses only shared overrides; a demo visitor's own overrides are applied per request.
module CacheWarmer
  DASHBOARD_REPLAYS = %w[2024-12-08 2025-01-05 2017-06-12 2017-12-31].freeze
  DISCOVER_REPLAYS = %w[2017-06-12].freeze

  module_function

  def call(logger: Rails.logger)
    started = Time.current
    products = step(logger, "store products") { ProductSource.call.products } || []
    dates = [Date.current] + DASHBOARD_REPLAYS.map { |d| Date.iso8601(d) }
    dates.each { |date| step(logger, "dashboard #{date}") { DashboardRows.fetch(products, as_of: date, overrides: OverrideSet.shared) } }
    ([Date.current] + DISCOVER_REPLAYS.map { |d| Date.iso8601(d) }).each do |date|
      step(logger, "discover #{date}") { DiscoverResults.fetch(date) }
    end
    logger.info("[cache warmer] done in #{(Time.current - started).round(1)}s")
  end

  # One failure (a Wikipedia or Shopify hiccup) shouldn't stop the rest. Returns nil on failure.
  def step(logger, name)
    yield
  rescue StandardError => e
    logger.warn("[cache warmer] #{name} failed: #{e.class}: #{e.message}")
    nil
  end
end
