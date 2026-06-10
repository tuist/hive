# syntax=docker/dockerfile:1.7

# Hive Condukt sandbox runtime. This is intentionally smaller than Tuist's
# GitHub Actions runner image: Condukt uses Kubernetes exec to run commands
# inside this long-lived pod, so the image only needs a practical Linux userland
# for coding tools, git workspace setup, and shell-driven validation.

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        locales \
        lsb-release \
        openssh-client \
        tar \
        unzip \
        wget \
        xz-utils \
        build-essential \
        autoconf \
        automake \
        libtool \
        pkg-config \
        cmake \
        ninja-build \
        m4 \
        bison \
        flex \
        gettext \
        libssl-dev \
        libffi-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        libncurses-dev \
        libxml2-dev \
        libxslt1-dev \
        libyaml-dev \
        libcurl4-openssl-dev \
        uuid-dev \
        zip \
        bzip2 \
        p7zip-full \
        file \
        git-lfs \
        postgresql-client \
        redis-tools \
        sqlite3 \
        ripgrep \
        fd-find \
        tree \
        less \
        vim-tiny \
        netcat-openbsd \
        dnsutils \
        iputils-ping \
        python3 \
        python3-pip \
        python3-venv \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -d /home/sandbox -s /bin/bash sandbox \
    && mkdir -p /workspace \
    && chown -R sandbox:sandbox /workspace /home/sandbox

USER sandbox
WORKDIR /workspace

CMD ["sleep", "infinity"]
