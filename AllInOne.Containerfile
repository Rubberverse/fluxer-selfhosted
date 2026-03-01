ARG BUILD_SHA
ARG BUILD_NUMBER
ARG BUILD_TIMESTAMP
ARG RELEASE_CHANNEL=nightly


#----------------------- Base image
FROM public.ecr.aws/docker/library/node:24-trixie-slim AS fluxer_builder

WORKDIR /usr/src/app
RUN corepack enable \
	&& corepack prepare pnpm@10.26.0 --activate

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      g++ \
      git \
      curl \
      make \
      curl \
      python3 \
      ca-certificates \
  && update-ca-certificates \
  && curl https://sh.rustup.rs -sSf | sh -s -- -y \
  && rm -rf /var/lib/apt/lists/*


#----------------------- fluxer_deps
FROM fluxer_builder AS fluxer_deps
WORKDIR /usr/src/app

COPY . .

RUN pnpm install --frozen-lockfile
RUN pnpm approve-builds msgpackr-extract@3.0.3 @parcel/watcher@2.5.6
RUN pnpm rebuild msgpackr-extract @parcel/watcher


#----------------------- fluxer_server
FROM fluxer_deps AS fluxer_server

RUN pnpm --filter @fluxer/config generate
RUN pnpm --filter @fluxer/marketing build:css
RUN pnpm --filter fluxer_server typecheck


#----------------------- fluxer_gateway
FROM public.ecr.aws/docker/library/erlang:28-slim AS fluxer_gateway
ARG LOGGER_LEVEL=info

COPY --from=fluxer_deps /usr/src/app /usr/src/app

WORKDIR /usr/src/app/gateway
RUN apt update \
	&& apt upgrade -y \
	&& apt install -y --no-install-recommends \
        git \
        curl \
        make \
        gcc \
        g++ \
        libc6-dev \
        ca-certificates \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app
RUN curl -fsSL https://github.com/erlang/rebar3/releases/download/3.24.0/rebar3 -o /usr/local/bin/rebar3 \
	&& chmod +x /usr/local/bin/rebar3 \
	&& rebar3 compile --deps_only

RUN LOGGER_LEVEL=${LOGGER_LEVEL} envsubst '${LOGGER_LEVEL}' < fluxer_gateway/config/vm.args.template > fluxer_gateway/config/vm.args \
    && LOGGER_LEVEL=${LOGGER_LEVEL} envsubst '${LOGGER_LEVEL}' < fluxer_gateway/config/sys.config.template > fluxer_gateway/config/sys.config

WORKDIR /usr/src/app/fluxer_gateway
RUN rebar3 as prod release


#----------------------- Rust builder stage
FROM fluxer_server AS fluxer_app

ARG BASE_DOMAIN
ARG FLUXER_CDN_ENDPOINT=${BASE_DOMAIN}

ENV PATH="/root/.cargo/bin:${PATH}"
ENV FLUXER_CONFIG=/tmp/fluxer-build-config.json
ENV FLUXER_CDN_ENDPOINT=${FLUXER_CDN_ENDPOINT}

WORKDIR /usr/src/app/fluxer_app
COPY config/config.production.template.json /tmp/fluxer-build-config.json

RUN sed -i "s/chat\.example\.com/${BASE_DOMAIN}/g" /tmp/fluxer-build-config.json \
    && pnpm lingui:compile \
    && pnpm build


#----------------------- Runner
FROM public.ecr.aws/docker/library/node:24-trixie-slim AS production

ARG BUILD_SHA
ARG BUILD_NUMBER
ARG BUILD_TIMESTAMP
ARG RELEASE_CHANNEL
ARG INCLUDE_NSFW_ML

LABEL org.opencontainers.image.title="Fluxer Server"
LABEL org.opencontainers.image.description="Unified Fluxer server for self-hosting - combines all backend services into a single deployable container"
LABEL org.opencontainers.image.vendor="Fluxer Contributors"
LABEL org.opencontainers.image.licenses="AGPL-3.0-or-later"LABEL org.opencontainers.image.source="https://github.com/fluxerapp/fluxer"
LABEL org.opencontainers.image.documentation="https://docs.fluxer.app"
LABEL org.opencontainers.image.revision="${BUILD_SHA}"
LABEL org.opencontainers.image.version="${BUILD_NUMBER}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

ENV NODE_ENV=production \
    TINI_SUBREAPER=1 \
    FLUXER_SERVER_HOST=0.0.0.0 \
    FLUXER_SERVER_PORT=8080 \
    FLUXER_GATEWAY_HOST=127.0.0.1 \
    FLUXER_GATEWAY_PORT=8082 \
    DATABASE_BACKEND=sqlite \
    SQLITE_PATH=/usr/src/app/data/db/fluxer.db \
    STORAGE_ROOT=/usr/src/app/data/storage \
    SEARCH_BACKEND=sqlite \
    FLUXER_SERVER_STATIC_DIR=/usr/src/app/assets \
    BUILD_SHA=${BUILD_SHA} \
    BUILD_NUMBER=${BUILD_NUMBER} \
    BUILD_TIMESTAMP=${BUILD_TIMESTAMP} \
    RELEASE_CHANNEL=${RELEASE_CHANNEL}

WORKDIR /usr/src/app
RUN apt update \
  && apt upgrade -y \
  && apt-get install -y --no-install-recommends \
      tini \
      curl \
      ffmpeg \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable \
	&& corepack prepare pnpm@10.26.0 --activate

COPY --from=fluxer_server --chown=node:node --chmod=555 /usr/src/app/node_modules ./node_modules
COPY --from=fluxer_server --chown=node:node --chmod=555 /usr/src/app/packages ./packages
COPY --from=fluxer_server --chown=node:node --chmod=555 /usr/src/app/fluxer_server ./fluxer_server
COPY --from=fluxer_server --chown=node:node --chmod=555 /usr/src/app/tsconfigs ./tsconfigs
COPY --from=fluxer_server --chown=node:node --chmod=555 /usr/src/app/pnpm-workspace.yaml ./
COPY --from=fluxer_server --chown=node:node --chmod=555 /usr/src/app/package.json ./
COPY --from=fluxer_gateway --chown=node:node --chmod=555 /usr/src/app/fluxer_gateway/_build/prod/rel/fluxer_gateway /opt/fluxer_gateway
COPY --from=fluxer_app --chown=node:node --chmod=555 /usr/src/app/fluxer_app/dist /usr/src/app/assets

RUN mkdir -p \
      /usr/src/app/data/storage \
      /usr/src/app/data/db \
      /opt/data \
      /data/s3 \
      /data/sqlite \
      /data/queue\
      /var/log/fluxer \
  && chown -R node:node /opt/data \
  && chown -R node:node /data

RUN --mount=type=bind,from=fluxer_deps,source=/usr/src/app/fluxer_media_proxy/data/model.onnx,target=/tmp/model.onnx \
    if [ "$INCLUDE_NSFW_ML" = "true" ]; then \
        echo "Including NSFW detection model..."; \
        cp /tmp/model.onnx /opt/data/model.onnx; \
    else \
        echo "Skipping NSFW detection model (INCLUDE_NSFW_ML=$INCLUDE_NSFW_ML)"; \
    fi

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
        CMD curl -f http://localhost:8080/_health || exit 1

EXPOSE 8080

USER node:node
ENTRYPOINT ["tini", "--", "pnpm", "--filter", "fluxer_server", "start"]
