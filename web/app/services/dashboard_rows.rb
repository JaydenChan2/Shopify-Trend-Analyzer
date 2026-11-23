require "digest"

# The dashboard's labelled rows, cached. Labelling ~20 products is cheap locally
# (~0.15s) but slow on Render's free CPU share (~1.5s), and the answer only changes
# when the week, the day (hindsight), the products or the overrides do, so those
# make the key. Visitors with no personal overrides share one entry, which the boot
# warmer fills; a demo visitor's own overrides give them their own entry.
module DashboardRows
  TTL = 12.hours

  module_function

  def fetch(products, as_of:, overrides:, wikipedia: WikipediaClient.new)
    key = ["dashboard-rows-v2", LiveLabel.last_complete_week_end(as_of), Date.current,
           fingerprint(products), overrides.fingerprint]
    Rails.cache.fetch(key, expires_in: TTL) do
      ProductTrend.rows(products, as_of: as_of, wikipedia: wikipedia, overrides: overrides)
    end
  end

  def fingerprint(products)
    Digest::SHA256.hexdigest(products.map { |p| [p[:id], p[:title], p[:product_type]] }.to_json)[0, 16]
  end
end
