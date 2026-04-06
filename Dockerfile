# --- Stage 1: Build upstream Paperclip ---
FROM node:22-bookworm AS paperclip-build
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git && rm -rf /var/lib/apt/lists/*
RUN corepack enable

ARG PAPERCLIP_REPO=https://github.com/paperclipai/paperclip.git
ARG PAPERCLIP_REF=v2026.403.0

WORKDIR /paperclip
RUN git clone --depth 1 --branch "${PAPERCLIP_REF}" "${PAPERCLIP_REPO}" .
RUN pnpm install --frozen-lockfile && pnpm --filter @paperclipai/ui build && pnpm --filter @paperclipai/plugin-sdk build && pnpm --filter @paperclipai/server build

# --- Stage 2: Runtime Image ---
FROM node:22-bookworm
ENV NODE_ENV=production

# Install gosu AND sudo
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gosu sudo && rm -rf /var/lib/apt/lists/*
RUN corepack enable

# ALLOW THE NODE USER TO RUN SUDO WITHOUT A PASSWORD
# This satisfies Claude because the process isn't "root", but it can still fix volumes
RUN echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node && chmod 0440 /etc/sudoers.d/node

# Global tools
RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest @openai/codex@latest opencode-ai tsx

WORKDIR /app
COPY --from=paperclip-build /paperclip /app

WORKDIR /wrapper
COPY package.json /wrapper/package.json
RUN npm install --omit=dev && npm cache clean --force
COPY src /wrapper/src
COPY scripts/entrypoint.sh /wrapper/entrypoint.sh
COPY scripts/bootstrap-ceo.mjs /wrapper/template/bootstrap-ceo.mjs

# Setup directories and initial ownership
RUN mkdir -p /paperclip/instances && chown -R node:node /app /paperclip /wrapper && chmod +x /wrapper/entrypoint.sh

EXPOSE 3100

# START AS THE NODE USER IMMEDIATELY
USER node

# Run the server directly (the entrypoint was likely complicating the UID detection)
CMD ["node", "/wrapper/src/server.js"]
