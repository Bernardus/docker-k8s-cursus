# ---- fase 1: bouwen ----------------------------------------------------------
FROM node:24-slim AS build
WORKDIR /app

# Eerst alleen de package-bestanden: deze laag blijft in de cache zolang je dependencies niet veranderen.
COPY package.json package-lock.json ./
RUN npm ci

# Dan de broncode, en TypeScript omzetten naar JavaScript.
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ---- fase 2: draaien ---------------------------------------------------------
FROM node:24-slim
WORKDIR /app
ENV NODE_ENV=production

# Alleen de dependencies die nodig zijn om te draaien (geen TypeScript e.d.).
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Alleen het resultaat uit fase 1, geen broncode.
COPY --from=build /app/dist ./dist

# Niet als root draaien.
USER node

EXPOSE 3000
CMD ["node", "dist/index.js"]
