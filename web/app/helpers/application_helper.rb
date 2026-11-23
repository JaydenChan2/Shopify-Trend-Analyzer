module ApplicationHelper
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
