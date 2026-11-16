# Stands in for WikipediaClient in tests: no network.
#   search(term)          -> canned result or { title: term.capitalize }
#   resolve_title(title)  -> canned result, or nil (no such article) by default
#   weekly_views(article) -> flat 3,000/week series ("No surge detected")
class FakeWikipedia
  attr_reader :series_requests

  def initialize(search: {}, resolve: {})
    @search, @resolve = search, resolve
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
    mondays.map { |m| [m, 3000] }
  end
end
