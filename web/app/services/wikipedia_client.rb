require "net/http"

# Wikipedia search + daily pageviews, cached with Rails.cache.
# Same data source and weekly bucketing (Mon-Sun from 2015-07-06) as the backtest.
class WikipediaClient
  class Error < StandardError; end
  class MissingContact < Error; end

  SEARCH_API = "https://en.wikipedia.org/w/api.php".freeze
  PAGEVIEWS_API = "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user".freeze
  DATA_START = Date.new(2015, 7, 1)
  FIRST_MONDAY = Date.new(2015, 7, 6) # backtest drops the partial first week too

  # Top Wikipedia article for a search term: { title:, redirect_from: } or nil.
  # redirect_from is set when the match came through a redirect, e.g. searching
  # "Air fryer" returns { title: "Convection oven", redirect_from: "Air fryer" }.
  def search(term)
    Rails.cache.fetch(["wiki-search-v2", term.downcase], expires_in: 7.days) do
      uri = URI(SEARCH_API)
      uri.query = URI.encode_www_form(action: "query", list: "search", srsearch: term, srlimit: 1,
                                      srnamespace: 0, srprop: "redirecttitle", format: "json")
      hit = JSON.parse(get(uri).body).dig("query", "search", 0)
      hit && { title: hit["title"], redirect_from: hit["redirecttitle"].presence }
    end
  end

  # Exact-title lookup, following redirects: { title:, redirected_from: } or nil if no such article.
  # Used to validate mapping overrides before saving them.
  def resolve_title(title)
    Rails.cache.fetch(["wiki-resolve-v1", title], expires_in: 1.day) do
      uri = URI(SEARCH_API)
      uri.query = URI.encode_www_form(action: "query", titles: title, redirects: 1, format: "json")
      query = JSON.parse(get(uri).body).fetch("query")
      page = query.fetch("pages").values.first
      next nil if page.key?("missing") || page.key?("invalid")

      redirect = query.fetch("redirects", []).first
      { title: page["title"], redirected_from: redirect && redirect["from"] }
    end
  end

  # [[monday, views], ...] for every week from 2015-07-06 up to the week ending `through` (a Sunday).
  def weekly_views(article, through:)
    daily = daily_views(article, through)
    weeks = []
    monday = FIRST_MONDAY
    while monday + 6 <= through
      weeks << [monday, (0..6).sum { |d| daily.fetch(monday + d, 0) }]
      monday += 7
    end
    weeks
  end

  private

  # { Date => views }. Missing days mean zero views (the API omits them).
  def daily_views(article, through)
    old_range = through < Date.current - 14
    Rails.cache.fetch(["wiki-daily-v1", article, through.iso8601], expires_in: old_range ? 30.days : 12.hours) do
      path = ERB::Util.url_encode(article.tr(" ", "_"))
      uri = URI("#{PAGEVIEWS_API}/#{path}/daily/#{DATA_START.strftime('%Y%m%d')}00/#{through.strftime('%Y%m%d')}00")
      response = get(uri, allow_404: true)
      next({}) if response.code == "404" # no views recorded at all

      JSON.parse(response.body).fetch("items").to_h do |item|
        [Date.strptime(item["timestamp"][0, 8], "%Y%m%d"), item["views"]]
      end
    end
  end

  def get(uri, allow_404: false)
    request = Net::HTTP::Get.new(uri, "User-Agent" => user_agent)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
      http.request(request)
    end
    return response if response.is_a?(Net::HTTPSuccess) || (allow_404 && response.code == "404")

    raise Error, "Wikipedia returned HTTP #{response.code} for #{uri.host}#{uri.path}"
  end

  # Wikimedia rejects requests without a descriptive User-Agent with contact info.
  def user_agent
    contact = ENV["WIKI_CONTACT"].presence or
      raise MissingContact, "Set WIKI_CONTACT (an email or URL) in .env; Wikipedia rejects anonymous clients."
    "SpikeOrStay/0.1 (#{contact})"
  end
end
