module ApplicationHelper
  DEFAULT_DESCRIPTION = "Spike or Stay is a Shopify app that labels surging products as a likely spike or a " \
                        "likely stayer, from six weeks of Wikipedia interest, and shows why. Backtested on 16 past trends."

  def page_title
    content_for(:title).presence || "Spike or Stay"
  end

  def page_description
    content_for(:description).presence || DEFAULT_DESCRIPTION
  end

  # The page without replay or UI params (?as_of, ?inline), so replays point at their page.
  # /trend keeps its article, since that's what the page is about.
  def canonical_url
    query = request.path == trend_path && params[:article].present? ? "?#{{ article: params[:article] }.to_query}" : ""
    "#{request.base_url}#{request.path}#{query}"
  end

  # The one date format for people: "Nov 6, 2017". (ISO stays for ?as_of= in URLs
  # and the technical "as_of = 2017-12-31" display.)
  def human_date(date)
    date.strftime("%b %-d, %Y")
  end

  # "May 29 – Jun 4, 2017" (the year once when both ends share it).
  def human_week_range(first, last)
    start = first.year == last.year ? first.strftime("%b %-d") : human_date(first)
    "#{start} – #{human_date(last)}"
  end
end
