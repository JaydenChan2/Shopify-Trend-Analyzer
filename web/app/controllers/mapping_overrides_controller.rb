# Merchant corrections to the product -> Wikipedia mapping (one per search term).
#   POST   /mapping_overrides       term=..., article=...   point the term at an article
#   POST   /mapping_overrides       term=..., ignored=1     "don't track" this term
#   DELETE /mapping_overrides/:id                           back to automatic search
# Every action redirects back to the table, keeping ?as_of so replays aren't lost.
#
# Who may change overrides:
#   OVERRIDES_PASSWORD set   -> anyone with the password (HTTP basic auth, username OVERRIDES_USER or "admin")
#   not set, development/test -> anyone (your own machine)
#   not set, production       -> nobody: on a public demo, visitors can't change what others see
class MappingOverridesController < ApplicationController
  # Tests swap in a fake so they never call Wikipedia.
  class_attribute :wikipedia_client, default: nil
  # True in production; tests flip it to check the public-demo behaviour.
  class_attribute :locked_without_password, default: Rails.env.production?

  before_action :require_editor

  def create
    override = MappingOverride.find_or_initialize_by(term_key: params[:term].to_s.strip.downcase)

    if params[:ignored].present?
      override.assign_attributes(ignored: true, article: nil)
      notice = "\"#{params[:term]}\" won't be tracked."
    else
      resolved = wikipedia.resolve_title(params[:article].to_s.strip) if params[:article].present?
      return back_to_table(alert: "No Wikipedia article called \"#{params[:article]}\".") if resolved.nil?

      override.assign_attributes(ignored: false, article: resolved[:title])
      notice = "\"#{params[:term]}\" now maps to \"#{resolved[:title]}\"."
      notice += " (\"#{resolved[:redirected_from]}\" redirects there.)" if resolved[:redirected_from]
    end

    if override.save
      back_to_table(notice: notice)
    else
      back_to_table(alert: override.errors.full_messages.to_sentence)
    end
  rescue WikipediaClient::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    back_to_table(alert: "Couldn't check Wikipedia: #{e.message}")
  end

  def destroy
    override = MappingOverride.find(params[:id])
    override.destroy
    back_to_table(notice: "Removed the override for \"#{override.term_key}\"; back to automatic search.")
  end

  private

  # A before_action: if it redirects or asks for a password, create/destroy never run.
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
      back_to_table(alert: "Fixing mappings is turned off on this public demo. Run the app locally to try it.")
    end
  end

  def wikipedia
    self.class.wikipedia_client || WikipediaClient.new
  end

  def back_to_table(flash_message)
    redirect_to dashboard_path(as_of: params[:as_of].presence), flash_message
  end
end
