# Merchant corrections to the product -> Wikipedia mapping (one per search term).
#   POST   /mapping_overrides   term=..., article=...   point the term at an article
#   POST   /mapping_overrides   term=..., ignored=1     "don't track" this term
#   DELETE /mapping_overrides   term=...                back to the default (automatic search)
# Every action redirects back to the dashboard, keeping ?as_of so replays aren't lost.
#
# Where a change is saved:
#   DEMO_MODE on  -> this visitor's session only (OverrideSet), on top of the seeded
#                    shared overrides. Anyone may try it; nobody else sees it.
#   otherwise     -> the database, for everyone. Who may change it:
#                      OVERRIDES_PASSWORD set     -> anyone with the password (HTTP basic auth,
#                                                    username OVERRIDES_USER or "admin")
#                      not set, development/test  -> anyone (your own machine)
#                      not set, production        -> nobody
class MappingOverridesController < ApplicationController
  # Tests swap in a fake so they never call Wikipedia.
  class_attribute :wikipedia_client, default: nil
  # True in production; tests flip it to check the locked behaviour.
  class_attribute :locked_without_password, default: Rails.env.production?

  before_action :require_editor, unless: -> { DemoMode.on? }
  # Saving checks the article title against Wikipedia: cap it per visitor (IP).
  rate_limit to: 20, within: 1.minute, only: :create, store: RATE_LIMIT_STORE,
             with: -> { back_to_table(alert: "Too many changes in a minute. Try again shortly.") }

  def create
    term = params[:term].to_s.strip
    return back_to_table(alert: "Missing search term.") if term.blank?

    if params[:ignored].present?
      save(term, ignored: true)
      notice = "\"#{term}\" won't be tracked."
    else
      article = params[:article].to_s.strip
      return back_to_table(alert: "That isn't a valid Wikipedia title.") if article.present? && !WikipediaTitle.valid?(article)

      resolved = wikipedia.resolve_title(article) if article.present?
      return back_to_table(alert: "No Wikipedia article called \"#{params[:article]}\".") if resolved.nil?

      save(term, article: resolved[:title])
      notice = "\"#{term}\" now maps to \"#{resolved[:title]}\"."
      notice += " (\"#{resolved[:redirected_from]}\" redirects there.)" if resolved[:redirected_from]
    end
    back_to_table(notice: notice + visitor_note)
  rescue ActiveRecord::RecordInvalid => e
    back_to_table(alert: e.record.errors.full_messages.to_sentence)
  rescue WikipediaClient::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    back_to_table(alert: "Couldn't check Wikipedia: #{e.message}")
  end

  def destroy
    term = OverrideSet.normalize(params[:term])
    if DemoMode.on?
      OverrideSet.for(session).remove_for_visitor(term)
    else
      MappingOverride.find_by(term_key: term)&.destroy
    end
    back_to_table(notice: "Removed the override for \"#{term}\"; back to the default mapping.#{visitor_note}")
  end

  private

  def save(term, article: nil, ignored: false)
    if DemoMode.on?
      OverrideSet.for(session).save_for_visitor(term, article: article, ignored: ignored)
    else
      override = MappingOverride.find_or_initialize_by(term_key: OverrideSet.normalize(term))
      override.update!(article: article, ignored: ignored)
    end
  end

  def visitor_note
    DemoMode.on? ? " Only you see this change: it's saved in your browser session on this demo." : ""
  end

  # A before_action (real stores only): if it redirects or asks for a password, create/destroy never run.
  def require_editor
    password = ENV["OVERRIDES_PASSWORD"].presence
    if password
      user = ENV["OVERRIDES_USER"].presence || "admin"
      # The browser shows its own username/password box; secure_compare avoids timing leaks.
      authenticate_or_request_with_http_basic("Mapping overrides") do |given_user, given_password|
        ActiveSupport::SecurityUtils.secure_compare(given_user, user) &
          ActiveSupport::SecurityUtils.secure_compare(given_password, password)
      end
    elsif locked_without_password
      back_to_table(alert: "Fixing mappings is turned off on this site.")
    end
  end

  def wikipedia
    self.class.wikipedia_client || WikipediaClient.new
  end

  def back_to_table(flash_message)
    redirect_to dashboard_path(as_of: params[:as_of].presence), flash_message
  end
end
