# syntax=docker.io/docker/dockerfile:1

FROM node:20-alpine AS base

RUN apk update \
  && apk add --no-cache libc6-compat openssl

WORKDIR /app

# =========================
# STAGE 1: DEPS
# Instala dependencias
# =========================
FROM base AS deps
WORKDIR /app

# Copiar archivos de dependencias
COPY package.json pnpm-lock.yaml ./

# Instalar dependencias
RUN corepack enable pnpm \
  && corepack prepare pnpm@9.15.4 --activate \
  && pnpm install --frozen-lockfile

# =========================
# STAGE 2: BUILDER
# Build de Next.js
# =========================
FROM base AS builder
WORKDIR /app

# Declarar ARGs que pueden ser pasados en build-time
# Estos valores se pasarán como --build-arg durante docker build
ARG NEXT_PUBLIC_API_URL
ARG NEXT_PUBLIC_ENVIRONMENT
ARG NEXT_PUBLIC_DEVELOP
ARG NEXT_PUBLIC_X_API_KEY
# Agrega aquí cualquier otro ARG que necesites

# Convertir ARGs a ENVs para que Next.js pueda accederlos durante el build
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_ENVIRONMENT=$NEXT_PUBLIC_ENVIRONMENT
ENV NEXT_PUBLIC_DEVELOP=$NEXT_PUBLIC_DEVELOP
ENV NEXT_PUBLIC_X_API_KEY=$NEXT_PUBLIC_X_API_KEY
ENV SKIP_ENV_VALIDATION=1

# Copiar node_modules desde deps
COPY --from=deps /app/node_modules ./node_modules

# Copiar código fuente
COPY . .

# Build de la aplicación
RUN corepack enable pnpm \
  && corepack prepare pnpm@9.15.4 --activate \
  && pnpm run build

# =========================
# STAGE 3: RUNNER
# Imagen final de producción
# =========================
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production

# Add curl for healthchecks
RUN apk add --no-cache curl

RUN addgroup --system --gid 1001 nodejs \
  && adduser --system --uid 1001 nextjs

USER nextjs

# Copiar el output standalone + static + public de la app
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# Optional: Add Docker HEALTHCHECK
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/api/health || exit 1

CMD ["node", "server.js"]
