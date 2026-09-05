FROM node:22.22.0-alpine AS dependencies
WORKDIR /app
COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/package.json
COPY apps/worker/package.json apps/worker/package.json
RUN npm ci && npm prune --omit=dev

FROM node:22.22.0-alpine
ENV NODE_ENV=production
WORKDIR /app
USER node
COPY --chown=node:node --from=dependencies /app/node_modules ./node_modules
COPY --chown=node:node apps/worker ./apps/worker
CMD ["node", "apps/worker/src/index.js"]
