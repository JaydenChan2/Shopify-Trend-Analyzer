# Discover classifies Wikipedia's most-read articles with Wikidata's "subclass of"
# graph (WikidataClient). Walking that graph from scratch takes ~30s per week, so
# a snapshot ships in db/wikidata_parents.json and only new types hit the network.
#
#   bin/rails discover:catalog            # last 12 weeks + the replay weeks below
#   WEEKS=26 bin/rails discover:catalog
#
# Re-run every month or two (or after changing WikidataClient::KINDS) and commit the file.
namespace :discover do
  # Replays linked from the README and the Discover page; keep them instant.
  REPLAY_DATES = %w[2017-06-12 2025-06-02].map { |d| Date.iso8601(d) }

  desc "Refresh db/wikidata_parents.json, the Wikidata type graph Discover ships with"
  task catalog: :environment do
    weeks = ENV.fetch("WEEKS", "12").to_i
    latest = LiveLabel.last_complete_week_end(Date.current)
    # Each Discover page pools the last LOOKBACK_WEEKS weeks, so cover all of them for the replays.
    replay_weeks = REPLAY_DATES.flat_map do |d|
      last = LiveLabel.last_complete_week_end(d)
      (0...TrendingProducts::LOOKBACK_WEEKS).map { |i| last - 7 * i }
    end
    week_ends = (0...weeks).map { |i| latest - 7 * i } + replay_weeks

    wikidata = WikidataClient.new
    finder = TrendingProducts.new(WikipediaClient.new, wikidata, Date.current)
    week_ends.uniq.each do |week_end|
      _, found = finder.products_for_week(week_end)
      puts "#{week_end}: #{found.size} products (#{found.keys.first(6).join(', ')}) | graph: #{wikidata.known_parents.size} types"
    rescue WikipediaClient::Error => e
      puts "#{week_end}: skipped (#{e.message}); run again later to fill it in"
    end

    graph = wikidata.known_parents.sort.to_h
    WikidataClient::CATALOG_PATH.write(JSON.generate(graph) + "\n")
    puts "Wrote #{graph.size} types to #{WikidataClient::CATALOG_PATH.relative_path_from(Rails.root)} " \
         "(#{(WikidataClient::CATALOG_PATH.size / 1024.0).round} KB)"
  end
end
