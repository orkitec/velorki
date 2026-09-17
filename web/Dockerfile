# Optional container image for forks that run the website + relay with Docker
# Compose. The official instance runs it with Orkify as a plain Node process
# instead - see ../docs/DEPLOY_WEB.md.
# syntax=docker/dockerfile:1
FROM node:26-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
# `next build` writes .next/standalone; the postbuild hook
# (scripts/standalone-assets.mjs) copies .next/static and public/ into it, so
# the standalone tree is self-contained: server.js, the traced node_modules,
# the content and message files and the assets.
RUN npm run build
# The share database lives outside the app tree. Created here because the
# distroless runtime has no shell to mkdir with. 65532 is `nonroot`.
RUN mkdir -p /var/lib/velorki && chown 65532:65532 /var/lib/velorki

FROM gcr.io/distroless/nodejs22-debian12:nonroot
# The standalone tree is the working directory, not its parent: content.ts,
# ai/provider.ts and site/screenshot-files.ts read `content/`, `src/ai/prompts/`
# and `public/screenshots/` relative to process.cwd(), and those exist inside
# the standalone tree - `next.config.ts` traces them there. Started from /app
# instead, POST /ai/plan would 500 on the missing prompts.
WORKDIR /app/.next/standalone
ENV NODE_ENV=production \
    PORT=8080 \
    HOSTNAME=0.0.0.0 \
    SHARE_DB_PATH=/var/lib/velorki/share.sqlite
COPY --from=build --chown=nonroot:nonroot /app/.next/standalone /app/.next/standalone
COPY --from=build --chown=nonroot:nonroot /app/.next/static /app/.next/standalone/.next/static
# public/ is already in the standalone tree: the postbuild hook
# (scripts/standalone-assets.mjs) copies it there.
COPY --from=build --chown=nonroot:nonroot /var/lib/velorki /var/lib/velorki
VOLUME ["/var/lib/velorki"]
EXPOSE 8080
# The distroless image's entrypoint is node, so this is the script argument,
# resolved against the WORKDIR above.
CMD ["server.js"]
