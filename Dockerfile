# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS issues that arise often.
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.3
ARG DEBIAN_VERSION=trixie-20260623-slim
ARG CHROMIUM_MIN_VERSION=150.0.7871.100
ARG RUNTIME_PACKAGE_REFRESH=static

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix compile
RUN mix assets.deploy

COPY config/runtime.exs config/

COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE}

ARG CHROMIUM_MIN_VERSION
ARG RUNTIME_PACKAGE_REFRESH

RUN apt-get update -y && \
  echo "Runtime package refresh: ${RUNTIME_PACKAGE_REFRESH}" && \
  apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates chromium fonts-noto-core fonts-noto-cjk \
  && installed_chromium_version="$(chromium --version | awk '{print $2}')" \
  && if ! dpkg --compare-versions "$installed_chromium_version" ge "$CHROMIUM_MIN_VERSION"; then \
    echo "Chromium $installed_chromium_version is older than required $CHROMIUM_MIN_VERSION" >&2; \
    exit 1; \
  fi \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/hive ./

USER nobody

CMD ["/app/bin/server"]
