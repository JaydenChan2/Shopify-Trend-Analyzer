# Builds the table rows: map every product, group products that map to the same
# Wikipedia article (15 snowboards -> one row), then label each group once.
# Errors are kept per row so one bad lookup doesn't break the page.
class ProductTrend
  # mapping:  the first product's mapping (drives the label and notes)
  # mappings: every distinct search term in the group, e.g. "snowboard" plus an
  #           overridden "The Minimal Snowboard", so each gets its own fix/remove form
  # article:  the article whose views were actually used (can differ from mapping.article in replays)
  # recent:   the last 26 complete weekly view counts, for the card's sparkline
  # hindsight: for replays, whether the call came true (Hindsight::Result), or nil
  # kinds:    Discover only: what Wikidata says it is, e.g. ["toy", "brand"]
  Row = Struct.new(:products, :mapping, :mappings, :article, :result, :notes, :error, :recent, :hindsight, :kinds,
                   keyword_init: true) do
    def initialize(**fields)
      super
      self.mappings ||= [mapping]
    end
  end

  # Rows with model calls first, unmapped last.
  LABEL_ORDER = ["Likely sustained", "Likely spike", "Surge detected – too early to tell",
                 "Possible surge (unconfirmed)", "No surge detected", "Not enough data", "Not mapped",
                 "Not tracked"].freeze

  def self.rows(products, as_of:, wikipedia: WikipediaClient.new, overrides: OverrideSet.shared)
    new(wikipedia, as_of, overrides).rows(products)
  end

  # The checks every tracked article gets, whether it came from the store or from
  # Discover: the live label as of `as_of`, the sparkline, and the hindsight check.
  def self.labelled_row(wikipedia, article, as_of, **fields)
    weeks = wikipedia.weekly_views(article, through: LiveLabel.last_complete_week_end(as_of))
    result = LiveLabel.call(weeks, as_of: as_of)
    Row.new(article: article, result: result, recent: weeks.last(26).map(&:last),
            hindsight: Hindsight.call(article: article, result: result, wikipedia: wikipedia), **fields)
  end

  def initialize(wikipedia, as_of, overrides = OverrideSet.shared)
    @wikipedia = wikipedia
    @as_of = as_of
    @mapper = ProductMapper.new(wikipedia: wikipedia, overrides: overrides)
  end

  def rows(products)
    mapped = products.map { |product| [product, @mapper.call(product)] }
    groups = mapped.group_by { |_, m| m.article ? "article:#{m.article}" : "unmapped:#{m.term.to_s.downcase}" }
    built = groups.values.map do |pairs|
      row = build_row(pairs.map(&:first), pairs.first.last)
      row.mappings = pairs.map(&:last).uniq { |m| m.term.downcase }
      row
    end
    built.sort_by { |row| [LABEL_ORDER.index(row.result&.label) || LABEL_ORDER.size, -row.products.size] }
  end

  private

  def build_row(products, mapping)
    if mapping.article.nil?
      label = mapping.ignored ? "Not tracked" : "Not mapped"
      return Row.new(products: products, mapping: mapping, notes: [],
                     result: LiveLabel::Result.new(label: label, reason: mapping.problem))
    end

    article, notes = series_article(mapping)
    self.class.labelled_row(@wikipedia, article, @as_of, products: products, mapping: mapping, notes: notes)
  rescue WikipediaClient::MissingContact
    raise # config problem: shown once at the top of the page, not per row
  rescue WikipediaClient::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    Row.new(products: products, mapping: mapping, article: mapping.article, notes: [], error: e.message)
  end

  # Which article's views to use, plus any warnings for the row.
  def series_article(mapping)
    redirect = mapping.redirected_from
    return [mapping.article, []] if redirect.nil?

    cutoff = StandaloneHistory.valid_until(redirect)
    if cutoff && @as_of <= cutoff
      [redirect, ["Replay: \"#{redirect}\" was its own article until #{cutoff.strftime('%b %-d, %Y')}, so its own views are used " \
                  "(today it redirects to \"#{mapping.article}\")."]]
    else
      [mapping.article, ["\"#{redirect}\" redirects to \"#{mapping.article}\" on Wikipedia, so these views are " \
                         "for the broader article, not the product itself."]]
    end
  end
end
