# What a Wikipedia title can be, so URL input is checked before any API call.
# Wikipedia titles are at most 255 bytes and can't contain # < > [ ] { } | or
# control characters (https://en.wikipedia.org/wiki/Wikipedia:Page_name).
module WikipediaTitle
  MAX_BYTES = 255
  FORBIDDEN = /[#<>\[\]{}|\p{Cc}]/

  module_function

  def valid?(title)
    title = title.to_s.strip
    title.present? && title.bytesize <= MAX_BYTES && !title.match?(FORBIDDEN)
  end
end
