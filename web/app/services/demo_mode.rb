# DEMO_MODE=true marks a public demo deploy (the live Render site), even when it's
# connected to a real (dev) store. In demo mode:
#   - mapping overrides a visitor makes live in their own session, on top of the
#     shared seeded ones, so nobody can change what other visitors see
#   - the header shows "Demo store" instead of the shop domain
# Without it, a connected store saves overrides for everyone (see MappingOverridesController).
module DemoMode
  module_function

  def on?
    ENV["DEMO_MODE"].to_s.strip.downcase.in?(%w[1 true yes on])
  end
end
