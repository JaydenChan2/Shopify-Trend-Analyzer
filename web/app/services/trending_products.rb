# Discover: finds products people are suddenly reading about, store or no store.
#
#   1. Candidates: for each of the last LOOKBACK_WEEKS complete weeks (as of `as_of`),
#      the 1,000 most-read Wikipedia articles on each day, summed; the top CANDIDATES
#      by weekly views. A single week holds only a few products, so the pool is every
#      product seen on the list in the lookback window.
#   2. Products only: Wikidata says what each one is (WikidataClient); people,
#      films, events, software etc. are dropped.
#   3. Same checks as store products: ProductTrend.labelled_row (live label,
#      sparkline, hindsight on replays).
#   4. Ranked by momentum (last week vs the 8 before); the top TOP_N are shown first.
#      Momentum only orders the list: labels still come from the onset rule and model.
#
# No lookahead: step 1 reads only days up to the replay's last complete week, and
# step 3 uses LiveLabel's usual truncation. Wikidata's classes are today's, which
# is fine: what a thing *is* doesn't leak how its trend turned out.
#
# Limitation: only the top 1,000 a day are visible, so a product needs roughly
# 10,000+ views a day to be found. Smaller surges need the product to be in a store.
class TrendingProducts
  CANDIDATES = 1000
  LOOKBACK_WEEKS = 4
  TOP_N = 5
  MOMENTUM_WEEKS = 8

  # top:    the TOP_N products with the most momentum, highest first
  # others: the rest of the pool, same order
  # scanned: distinct candidate articles checked; lookback_start..week_end: the pool's window
  Result = Struct.new(:top, :others, :scanned, :lookback_start, :week_start, :week_end, keyword_init: true)

  # Last week's views over the median of the MOMENTUM_WEEKS before it (+1 on both,
  # so a brand-new article with no history still ranks instead of dividing by 0).
  def self.momentum(values)
    return nil if values.size < 2

    before = values[-(MOMENTUM_WEEKS + 1)...-1] || values[0...-1]
    (values.last + 1.0) / (TrendMath.median(before) + 1.0)
  end

  NON_ARTICLE = /\A(Main Page|-|(Special|Wikipedia|File|Portal|Help|Talk|User|Template|Category|Draft|Module|MediaWiki)( talk)?:)/

  def self.call(as_of:, wikipedia: WikipediaClient.new, wikidata: WikidataClient.new)
    new(wikipedia, wikidata, as_of).call
  end

  def initialize(wikipedia, wikidata, as_of)
    @wikipedia, @wikidata, @as_of = wikipedia, wikidata, as_of
  end

  def call
    week_end = LiveLabel.last_complete_week_end(@as_of)
    weeks = (0...LOOKBACK_WEEKS).map { |i| week_end - 7 * i }
    scanned = Set.new
    found = {}
    weeks.each do |w|
      candidates, products = products_for_week(w)
      scanned.merge(candidates)
      products.each { |article, kinds| found[article] ||= kinds }
    end
    rows = in_parallel(found.to_a) do |article, kinds|
      row = ProductTrend.labelled_row(@wikipedia, article, @as_of, products: [{ title: article }], mapping: nil,
                                      notes: [], kinds: kinds)
      row.momentum = self.class.momentum(row.recent)
      row
    end
    ranked = rows.sort_by { |row| [-(row.momentum || 0), ProductTrend::LABEL_ORDER.index(row.result.label) || 99] }
    Result.new(top: ranked.first(TOP_N), others: ranked.drop(TOP_N), scanned: scanned.size,
               lookback_start: weeks.last - 6, week_start: week_end - 6, week_end: week_end)
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
    in_parallel(week.to_a) { |day| @wikipedia.top_articles(day) }.each do |articles|
      articles.each { |title, views| totals[title] += views }
    end
    totals.reject { |title, _| title.match?(NON_ARTICLE) }.max_by(CANDIDATES, &:last).map(&:first)
  end

  # Network waits (Wikipedia lists, pageview series), PARALLEL at a time, results in order.
  def in_parallel(items, &block)
    items.each_slice(WikimediaHttp::PARALLEL).flat_map do |group|
      group.map { |item| Thread.new { block.call(item) } }.map(&:value)
    end
  end

  # { "Canonical title" => ["toy", ...] } for candidates Wikidata calls products.
  def products(titles)
    items = @wikipedia.wikidata_items(titles) # title => [canonical, qid]
    kinds = @wikidata.product_kinds(items.values.map(&:last))
    items.values.uniq.filter_map { |canonical, qid| [canonical, kinds[qid]] if kinds[qid] }.to_h
  end

end
