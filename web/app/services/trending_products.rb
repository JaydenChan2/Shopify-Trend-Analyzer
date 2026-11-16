# Discover: finds products people are suddenly reading about, store or no store.
#
#   1. Candidates: the 1,000 most-read Wikipedia articles on each day of the last
#      complete week (as of `as_of`), summed; the top CANDIDATES by weekly views.
#   2. Products only: Wikidata says what each one is (WikidataClient); people,
#      films, events, software etc. are dropped.
#   3. Same checks as store products: ProductTrend.labelled_row (live label,
#      sparkline, hindsight on replays).
#
# No lookahead: step 1 reads only days up to the replay's last complete week, and
# step 3 uses LiveLabel's usual truncation. Wikidata's classes are today's, which
# is fine: what a thing *is* doesn't leak how its trend turned out.
#
# Limitation: only the top 1,000 a day are visible, so a product needs roughly
# 10,000+ views a day to be found. Smaller surges need the product to be in a store.
class TrendingProducts
  CANDIDATES = 1000

  # surging: rows with a surge in the last 10 weeks (the four surge labels)
  # steady:  products that are heavily read but didn't jump
  Result = Struct.new(:surging, :steady, :scanned, :week_start, :week_end, keyword_init: true)

  NON_ARTICLE = /\A(Main Page|-|(Special|Wikipedia|File|Portal|Help|Talk|User|Template|Category|Draft|Module|MediaWiki)( talk)?:)/

  def self.call(as_of:, wikipedia: WikipediaClient.new, wikidata: WikidataClient.new)
    new(wikipedia, wikidata, as_of).call
  end

  def initialize(wikipedia, wikidata, as_of)
    @wikipedia, @wikidata, @as_of = wikipedia, wikidata, as_of
  end

  def call
    week_end = LiveLabel.last_complete_week_end(@as_of)
    candidates, found = products_for_week(week_end)
    rows = found.map do |article, kinds|
      ProductTrend.labelled_row(@wikipedia, article, @as_of, products: [{ title: article }], mapping: nil, notes: [],
                                kinds: kinds)
    end
    surging, steady = rows.partition { |row| row.result.onset_week }
    Result.new(surging: sort(surging), steady: sort(steady), scanned: candidates.size,
               week_start: week_end - 6, week_end: week_end)
  end

  # Steps 1-2 for the week ending `week_end`: [candidate titles, { article => kinds }].
  # Public so lib/tasks/discover.rake can warm the Wikidata catalog.
  def products_for_week(week_end)
    candidates = most_read((week_end - 6)..week_end)
    [candidates, products(candidates)]
  end

  private

  # Top CANDIDATES titles by total views over the week.
  def most_read(week)
    totals = Hash.new(0)
    week.each { |day| @wikipedia.top_articles(day).each { |title, views| totals[title] += views } }
    totals.reject { |title, _| title.match?(NON_ARTICLE) }.max_by(CANDIDATES, &:last).map(&:first)
  end

  # { "Canonical title" => ["toy", ...] } for candidates Wikidata calls products.
  def products(titles)
    items = @wikipedia.wikidata_items(titles) # title => [canonical, qid]
    kinds = @wikidata.product_kinds(items.values.map(&:last))
    items.values.uniq.filter_map { |canonical, qid| [canonical, kinds[qid]] if kinds[qid] }.to_h
  end

  def sort(rows)
    rows.sort_by { |row| [ProductTrend::LABEL_ORDER.index(row.result.label) || 99, -row.recent.last.to_i] }
  end
end
