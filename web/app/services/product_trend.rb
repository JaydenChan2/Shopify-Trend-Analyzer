# One table row: product -> mapping -> weekly views -> live label.
# Errors are kept per row so one bad lookup doesn't break the page.
class ProductTrend
  Row = Struct.new(:product, :mapping, :result, :error, keyword_init: true)

  def self.call(product, as_of:, wikipedia: WikipediaClient.new)
    mapping = ProductMapper.new(wikipedia: wikipedia).call(product)
    if mapping.article.nil?
      reason = "Wikipedia search found no article for \"#{mapping.term}\". Needs a mapping override (see ProductMapper TODO)."
      return Row.new(product: product, mapping: mapping, result: LiveLabel::Result.new(label: "Not mapped", reason: reason))
    end

    weeks = wikipedia.weekly_views(mapping.article, through: LiveLabel.last_complete_week_end(as_of))
    Row.new(product: product, mapping: mapping, result: LiveLabel.call(weeks, as_of: as_of))
  rescue WikipediaClient::MissingContact
    raise # config problem: show it once at the top of the page, not per row
  rescue WikipediaClient::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    Row.new(product: product, mapping: mapping, error: e.message)
  end
end
