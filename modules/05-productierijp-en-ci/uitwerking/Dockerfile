# ---- fase 1: bouwen ----------------------------------------------------------
# --platform=$BUILDPLATFORM: deze fase draait altijd op de architectuur van de bouwer zelf
# (snel), ook als we voor een andere architectuur bouwen. Het resultaat is JavaScript, en dat
# werkt overal.
FROM --platform=$BUILDPLATFORM node:24-slim AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ---- fase 2: draaien ---------------------------------------------------------
FROM node:24-slim
WORKDIR /app

# Versie die de pipeline meegeeft: podman build --build-arg APP_VERSION=...
ARG APP_VERSION=dev
ENV NODE_ENV=production \
    APP_VERSION=$APP_VERSION
LABEL org.opencontainers.image.title="snip-api" \
      org.opencontainers.image.version=$APP_VERSION

# Beveiligingsupdates van Debian die nog niet in het basis-image zitten.
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

# Alleen productie-dependencies. Daarna npm zelf weg: de app heeft het niet nodig om te draaien,
# en elk programma minder is een kwetsbaarheid minder.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

COPY --from=build /app/dist ./dist

USER node

EXPOSE 3000
CMD ["node", "dist/index.js"]
