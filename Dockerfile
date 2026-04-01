# --- Stage 1: Build upstream Paperclip ---
FROM node:22-bookworm AS paperclip-build
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*
RUN corepack enable

ARG PAPERCLIP_REPO=https://github.com/paperclipai/paperclip.git
ARG PAPERCLIP_REF=v2026.325.0

WORKDIR /paperclip
RUN git clone --depth 1 --branch "${PAPERCLIP_REF}" "${PAPERCLIP_REPO}" .
RUN pnpm install --frozen-lockfile
RUN pnpm --filter @paperclipai/ui build
RUN pnpm --filter @paperclipai/plugin-sdk build
RUN pnpm --filter @paperclipai/server build
RUN test -f server/dist/index.js

# --- Stage 2: Runtime Image ---
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gosu \
    && rm -rf /var/lib/apt/lists/*
RUN corepack enable

# Global tools installation (Claude Code CLI, etc.)
RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest @openai/codex@latest opencode-ai tsx

# Setup application directories
WORKDIR /app
COPY --from=paperclip-build /paperclip /app

WORKDIR /wrapper
COPY package.json /wrapper/package.json
RUN npm install --omit=dev && npm cache clean --force
COPY src /wrapper/src
COPY scripts/entrypoint.sh /wrapper/entrypoint.sh
COPY scripts/bootstrap-ceo.mjs /wrapper/template/bootstrap-ceo.mjs
RUN chmod +x /wrapper/entrypoint.sh

# --- PERMISSIONS FIX FOR CLAUDE CODE ---
# 1. Create the persistent data directory
RUN mkdir -p /paperclip/instances

# 2. Ensure the built-in 'node' user owns everything it needs to touch
RUN chown -R node:node /app /paperclip /wrapper

# 3. Expose the Railway port
EXPOSE 3100

# 4. Switch to the non-root 'node' user. 
# This is what prevents the "--dangerously-skip-permissions" error.
USER node

# 5. Start the server
# We use the direct node command to ensure the process runs as the 'node' user
CMD ["node", "/wrapper/src/server.js"]
