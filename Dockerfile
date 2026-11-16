# Production image for the Rails app in web/. Built from the repo root because the app
# reads ../backtest/model.json and ../backtest/trends.csv at runtime.
#
#   docker build -t spike-or-stay .
#   docker run -p 3000:3000 -e SECRET_KEY_BASE=$(openssl rand -hex 64) -e WIKI_CONTACT=you@example.com spike-or-stay
#
# Render builds this automatically from render.yaml.

ARG RUBY_VERSION=3.4.11
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails/web

# sqlite3 CLI is handy for poking at the database from a Render shell; tzdata for time zones.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y sqlite3 tzdata && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# ---- Build stage: gems and precompiled assets ----
FROM base AS build

# Puma, nio4r, json, bigdecimal and a few others compile C extensions during
# bundle install. The compiler lives in this stage only; the final image just
# copies the built gems.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential pkg-config libyaml-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY web/Gemfile web/Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache

COPY web/ ./
COPY backtest/model.json backtest/trends.csv /rails/backtest/

# Assets are compiled without the real secret.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# ---- Final stage: no build leftovers, runs as a non-root user ----
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p db log storage tmp && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

ENTRYPOINT ["/rails/web/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
