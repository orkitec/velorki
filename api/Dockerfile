# Optional container image for forks that run the relay with Docker Compose.
# The official instance runs it with Orkify as a plain Node process instead.
# syntax=docker/dockerfile:1
FROM node:24-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build && npm prune --omit=dev

FROM gcr.io/distroless/nodejs24-debian12:nonroot
WORKDIR /app
ENV NODE_ENV=production PORT=8080 SHARE_DB_PATH=/app/data/share.sqlite
COPY --from=build --chown=nonroot:nonroot /app/dist ./dist
COPY --from=build --chown=nonroot:nonroot /app/node_modules ./node_modules
COPY --from=build --chown=nonroot:nonroot /app/package.json ./package.json
VOLUME ["/app/data"]
EXPOSE 8080
CMD ["dist/server.js"]
