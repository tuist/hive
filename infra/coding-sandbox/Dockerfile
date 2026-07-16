ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.3
ARG DEBIAN_VERSION=trixie-20260623-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}

RUN apt-get update -y && \
  apt-get install -y --no-install-recommends build-essential ca-certificates curl git ripgrep && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1000 sandbox && \
  useradd --uid 1000 --gid sandbox --create-home --shell /bin/bash sandbox && \
  mkdir -p /workspace && chown sandbox:sandbox /workspace

ENV HOME=/home/sandbox
WORKDIR /workspace
USER 1000:1000

CMD ["sleep", "infinity"]
