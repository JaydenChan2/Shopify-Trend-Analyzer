# Discover's result for a date, cached. Every as_of in the same week gives the same
# answer, and hindsight depends on today, so the key is (week, today).
# Shared by DiscoverController and CacheWarmer so they hit the same cache entry.
module DiscoverResults
  module_function

  def fetch(as_of, wikipedia: WikipediaClient.new, wikidata: WikidataClient.new)
    key = ["discover-v2", LiveLabel.last_complete_week_end(as_of), Date.current]
    Rails.cache.fetch(key, expires_in: 1.day) do
      TrendingProducts.call(as_of: as_of, wikipedia: wikipedia, wikidata: wikidata)
    end
  end
end
