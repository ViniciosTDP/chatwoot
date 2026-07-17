FROM ruby:3.4.4-bookworm

ARG PNPM_VERSION=10.2.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libpq-dev postgresql-client imagemagick libvips-dev \
    git curl libyaml-dev libffi-dev \
    && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g pnpm@${PNPM_VERSION} \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV BUNDLE_PATH=/bundle
ENV PNPM_HOME=/root/.local/share/pnpm
ENV PATH="$PNPM_HOME:$PATH"

COPY docker/entrypoints/dev-local.sh /usr/local/bin/dev-local.sh
RUN sed -i 's/\r$//' /usr/local/bin/dev-local.sh && chmod +x /usr/local/bin/dev-local.sh

EXPOSE 3000 3036
ENTRYPOINT ["/usr/local/bin/dev-local.sh"]
