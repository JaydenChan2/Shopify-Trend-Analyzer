# Static marketing pages. No API calls, so they load instantly.
# (Not "method": that name is a built-in Ruby method every object has.)
class PagesController < ApplicationController
  def home; end

  def methodology; end
end
