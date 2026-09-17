# Optional container image for forks that run the website + relay with Docker
# Compose. The official instance runs it with Orkify as a plain Node process
# instead - see ../docs/DEPLOY_WEB.md.
# syntax=docker/dockerfile:1
FROM node:22-slim AS build
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
WORKDIR /app
ENV NODE_ENV=production \
    PORT=8080 \
    HOSTNAME=0.0.0.0 \
    SHARE_DB_PATH=/var/lib/velorki/share.sqlite
# Kept at the same path the repo uses everywhere else (package.json's `start`,
# orkify.yml's `script`), so there is one entry point to remember.
COPY --from=build --chown=nonroot:nonroot /app/.next/standalone ./.next/standalone
COPY --from=build --chown=nonroot:nonroot /app/.next/static ./.next/standalone/.next/static
COPY --from=build --chown=nonroot:nonroot /app/public ./.next/standalone/public
COPY --from=build --chown=nonroot:nonroot /var/lib/velorki /var/lib/velorki
VOLUME ["/var/lib/velorki"]
EXPOSE 8080
# The distroless image's entrypoint is node, so this is the script argument.
CMD [".next/standalone/server.js"]
