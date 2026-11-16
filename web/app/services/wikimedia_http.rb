require "net/http"

# Shared GET for Wikipedia, the pageviews API and Wikidata. Wikimedia rejects
# requests without a descriptive User-Agent with contact info (WIKI_CONTACT).
module WikimediaHttp
  MAX_RETRIES = 3 # on HTTP 429 (rate limited, like backtest/wiki.py) and 502-504 (Wikidata's query service is often busy)
  RETRY_CODES = %w[429 502 503 504].freeze

  PARALLEL = 4 # Wikidata's query service allows 5 concurrent queries per client

  private

  # Runs the block on each batch, PARALLEL at a time (the calls are just network
  # waits), and returns the results in order. Errors are re-raised in the caller.
  def in_parallel(batches, &block)
    batches.each_slice(PARALLEL).flat_map do |group|
      group.map { |batch| Thread.new { block.call(batch) } }.map(&:value)
    end
  end

  def get(uri, allow_404: false, accept: nil, read_timeout: 20)
    attempt = 0
    loop do
      request = Net::HTTP::Get.new(uri, { "User-Agent" => user_agent, "Accept" => accept }.compact)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: read_timeout) do |http|
        http.request(request)
      end
      return response if response.is_a?(Net::HTTPSuccess) || (allow_404 && response.code == "404")

      if RETRY_CODES.include?(response.code) && attempt < MAX_RETRIES
        attempt += 1
        wait = response["Retry-After"].to_i.clamp(1, 30)
        sleep(response["Retry-After"] ? wait : 2**attempt)
        next
      end
      raise WikipediaClient::Error, "Wikimedia returned HTTP #{response.code} for #{uri.host}#{uri.path}"
    end
  end

  def user_agent
    contact = ENV["WIKI_CONTACT"].presence or
      raise WikipediaClient::MissingContact, "Set WIKI_CONTACT (an email or URL) in .env; Wikipedia rejects anonymous clients."
    "SpikeOrStay/0.1 (#{contact})"
  end
end
