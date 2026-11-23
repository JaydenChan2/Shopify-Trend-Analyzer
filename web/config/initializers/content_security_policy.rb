# Content Security Policy: everything comes from this origin.
#
#   scripts      app.js only, plus the inline theme script in the layout via a per-request nonce
#   stylesheets  application.css only (no inline <style>, no third-party CSS)
#   style=""     allowed on elements: the contribution bars and the homepage mock set
#                data-driven widths (style="width: 42%"). Values are ERB-escaped.
#   images       this origin and data: URIs; no plugins; forms post only here; no framing
#
# The static error pages in public/ are served without this header (they have inline
# styles so they still render when the app itself is down).
# See https://guides.rubyonrails.org/security.html#content-security-policy-header
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self
    policy.style_src_elem :self
    policy.style_src_attr :unsafe_inline
    policy.img_src :self, :data
    policy.font_src :self, :data
    policy.connect_src :self
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
  end

  # A fresh nonce per request for the one inline <script> (the theme toggle).
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
