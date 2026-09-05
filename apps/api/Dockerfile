FROM node:22.22.0-alpine AS dependencies
WORKDIR /app
COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/package.json
COPY apps/worker/package.json apps/worker/package.json
RUN npm ci
COPY apps/api/prisma apps/api/prisma
RUN npm --workspace @paisa/api run prisma:generate && npm prune --omit=dev

FROM node:22.22.0-alpine
ENV NODE_ENV=production AUTH_MODE=firebase APP_CHECK_MODE=enforce
WORKDIR /app
USER node
COPY --chown=node:node --from=dependencies /app/node_modules ./node_modules
COPY --chown=node:node apps/api ./apps/api
EXPOSE 4000
CMD ["node", "apps/api/src/server.js"]
