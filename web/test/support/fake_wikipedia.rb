# Stands in for WikipediaClient in tests: no network.
#   search(term)          -> canned result or { title: term.capitalize }
#   resolve_title(title)  -> canned result, or nil (no such article) by default
#   weekly_views(article) -> flat 3,000/week ("No surge detected"), or a custom
#                            series for that article whose LAST value lands on the
#                            last complete week (earlier weeks padded with 1,000)
class FakeWikipedia
  attr_reader :series_requests

  def initialize(search: {}, resolve: {}, series: {})
    @search, @resolve, @series = search, resolve, series
    @series_requests = []
  end

  def search(term)
    @search.fetch(term) { { title: term.capitalize, redirect_from: nil } }
  end

  def resolve_title(title)
    @resolve[title]
  end

  def weekly_views(article, through:)
    @series_requests << article
    mondays = (WikipediaClient::FIRST_MONDAY..through).step(7).select { |m| m + 6 <= through }
    custom = @series[article]
    return mondays.map { |m| [m, 3000] } unless custom

    padded = Array.new([mondays.size - custom.size, 0].max, 1000) + custom.last(mondays.size)
    mondays.zip(padded)
  end
end

# Like FakeWikipedia, but each custom series is a block of the week's Monday, so
# the same calendar week has the same views however far `through` reaches
# (hindsight fetches past a replay's as_of). Other articles stay flat at 3,000.
class DatedFakeWikipedia < FakeWikipedia
  def initialize(dated: {}, **options)
    super(**options)
    @dated = dated
  end

  def weekly_views(article, through:)
    rule = @dated[article] or return super
    @series_requests << article
    (WikipediaClient::FIRST_MONDAY..through).step(7).select { |m| m + 6 <= through }.map { |m| [m, rule.call(m)] }
  end
end
