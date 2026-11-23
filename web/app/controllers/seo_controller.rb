# /sitemap.xml and /robots.txt, generated so they carry the deploy's own host.
class SeoController < ApplicationController
  PAGES = [["/", "weekly", "1.0"], ["/discover", "daily", "0.8"], ["/how-it-works", "monthly", "0.7"],
           ["/dashboard", "daily", "0.6"]].freeze

  def sitemap
    render formats: :xml
  end

  def robots
    render plain: <<~ROBOTS
      User-agent: *
      Disallow: /dashboard/cards
      Disallow: /discover/results
      Disallow: /mapping_overrides

      Sitemap: #{request.base_url}/sitemap.xml
    ROBOTS
  end
end
