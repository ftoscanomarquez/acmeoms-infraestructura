# ── Dockerfile del OMS ────────────────────────────────────────────
# Multi-stage. Cumple la spec del Vídeo 1:
#   ✓ usuario no-root (UID > 10000)
#   ✓ HEALTHCHECK contra /health
#   ✓ Labels OCI con trazabilidad
#   ✓ Tamaño minimizado (slim runtime)
#   ✓ Cero secretos en capas
#
# NOTA: el endpoint es /health, NO /healthz — ver server.js para el
# hallazgo real (GFE intercepta /healthz antes de llegar al contenedor
# en Cloud Run).
#
# Estamos asumiendo Node.js como ejemplo. Si el OMS está en Python o Java,
# adapta las imágenes base pero MANTÉN la estructura multi-stage.

# syntax=docker/dockerfile:1.6

# NODE_BASE parametriza la imagen base de ambas etapas — usado por el job
# "ci" del pipeline (.github/workflows/ci-cd.yml) para probar el build en
# matriz contra más de una versión de Node sin duplicar el Dockerfile.
# Un ARG antes del primer FROM está disponible en TODOS los FROM del
# archivo (a diferencia de un ARG declarado después de un FROM, que solo
# aplica a esa etapa en adelante).
ARG NODE_BASE=22-alpine

# ─── Etapa 1: builder ─────────────────────────────────────────────
FROM node:${NODE_BASE} AS deps
WORKDIR /app

# Aprovechar cache: solo invalidar pip install si requirements cambia
COPY package.json package-lock.json ./
# NOTA DE DISEÑO (agregado por el equipo): el placeholder actual (server.js,
# solo módulos nativos de Node) no tiene NINGUNA dependencia de terceros —
# "npm ci" con un package.json sin `dependencies` no crea node_modules en
# absoluto (no hay nada que instalar). Se crea el directorio explícitamente
# para que el `COPY --from=deps` de la etapa de runtime nunca falle por
# "file does not exist", sea cual sea el estado de las dependencias reales
# que la aplicación OMS termine necesitando en el futuro.
RUN npm ci --omit=dev && mkdir -p node_modules

# ─── Etapa 2: runtime ─────────────────────────────────────────────
FROM node:${NODE_BASE}
WORKDIR /app

# Usuario no-root con UID alto
RUN addgroup -g 10001 oms && \
    adduser  -u 10001 -G oms -s /bin/false -D oms

# Copiar solo los node_modules de la etapa anterior (sin compilador)
COPY --from=deps /app/node_modules ./node_modules

# Copiar el código de la app
COPY . .

USER oms

ENV NODE_ENV=production \
    PORT=8080

EXPOSE 8080

# Healthcheck para Cloud Run (también lo usa el HTTPS LB en su health check)
# Notación JSON (exec form) en vez de shell form — hadolint DL3025:
# evita pasar por /bin/sh y su interpretación de caracteres especiales.
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
  CMD ["wget", "-qO-", "http://127.0.0.1:8080/health"]

# NOTA DE DISEÑO (agregado por el equipo): labels OCI completos para
# trazabilidad. `revision` se pasa como ARG en el momento del build (no
# hardcodeado) porque cambia en cada commit — ver comando de build en
# BITACORA-COMANDOS.md Fase 3. `created` también se inyecta en build-time
# (la fecha de build, no la de escritura de este Dockerfile).
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.source="https://github.com/ftoscanomarquez/acmeoms-infraestructura" \
      org.opencontainers.image.version="0.2.0" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AcmeOMS" \
      org.opencontainers.image.title="oms-platform" \
      org.opencontainers.image.description="AcmeOMS — infraestructura del monolito modular OMS (ver anexo-arquitectura/03-arquitectura.md). Esta imagen, mientras no exista la app real, corre un placeholder minimo (server.js) unicamente para fines de despliegue de infraestructura."

CMD ["node", "server.js"]
