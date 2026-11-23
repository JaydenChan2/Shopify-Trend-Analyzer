# Warm the Wikipedia/Wikidata cache in the background once the web server boots
# (see app/services/cache_warmer.rb). Only for `rails server` in production, so
# tests, the console and rake tasks never start it. WARM_CACHE=0 turns it off.
Rails.application.config.after_initialize do
  next unless Rails.env.production? && defined?(Rails::Server) && ENV["WARM_CACHE"] != "0"

  Thread.new do
    sleep 1 # let Puma finish booting and take the first request
    Rails.application.executor.wrap { CacheWarmer.call }
  end
end
