FROM ruby:3.1.3-slim AS builder

# skipcq: DOK-DL3008
RUN set -eux; \
    apt-get update -y ; \
    apt-get dist-upgrade -y ; \
    apt-get install git gcc make libpq-dev libjemalloc2 shared-mime-info --no-install-recommends -y ; \
    apt-get autoremove -y ; \
    apt-get clean -y ; \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app

WORKDIR /app

COPY .ruby-version .ruby-version

COPY Gemfile Gemfile

COPY Gemfile.lock Gemfile.lock

ENV RAILS_ENV production

ENV RAILS_LOG_TO_STDOUT true

ENV RUBYGEMS_VERSION 3.3.26

RUN gem update --system "$RUBYGEMS_VERSION"

ENV BUNDLER_VERSION 2.3.26

# skipcq: DOK-DL3028
RUN gem install bundler --version "$BUNDLER_VERSION" --force

RUN gem --version

RUN bundle --version

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config set --global frozen 1

# two jobs
RUN bundle config set --global jobs 2

# install only production gems without development and test
RUN bundle config set --global without development test

# retry 5 times before fail
RUN bundle config set --global retry 5

RUN bundle install

RUN rm -rf /usr/local/bundle/cache/*.gem

RUN find /usr/local/bundle/gems/ -name "*.c" -delete

RUN find /usr/local/bundle/gems/ -name "*.o" -delete

COPY . .

RUN bundle exec bootsnap precompile --gemfile app/ lib/

# The SECRET_KEY_BASE here isn't used. Precomiling assets doesn't use your
# secret key, but Rails will fail to initialize if it isn't set.

RUN bundle exec rake SECRET_KEY_BASE=no \
    DATABASE_URL="postgres://postgres@postgresql/evemonk_production?pool=1&encoding=unicode" \
    assets:precompile

FROM ruby:3.1.3-slim

LABEL maintainer="Igor Zubkov <igor.zubkov@gmail.com>"

# skipcq: DOK-DL3008
RUN set -eux; \
    apt-get update -y ; \
    apt-get dist-upgrade -y ; \
    apt-get install libpq5 curl libjemalloc2 shared-mime-info --no-install-recommends -y ; \
    apt-get autoremove -y ; \
    apt-get clean -y ; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN groupadd --gid 1000 app

RUN useradd --uid 1000 --no-log-init --create-home --gid app app

USER app

COPY --from=builder /usr/local/bundle/ /usr/local/bundle/
COPY --from=builder /usr/local/bin/ /usr/local/bin/
COPY --from=builder --chown=app:app /app /app

# install only production gems without development and test
RUN bundle config set --global without development test

ARG COMMIT=""

ENV COMMIT_SHA=${COMMIT}

ENV RAILS_ENV production

ENV RAILS_LOG_TO_STDOUT true

ENV RAILS_SERVE_STATIC_FILES true

ENV BOOTSNAP_LOG true

ENV BOOTSNAP_READONLY true

ENV LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

EXPOSE 3000/tcp

ENTRYPOINT ["bundle", "exec", "puma", "-C", "config/puma.rb"]
