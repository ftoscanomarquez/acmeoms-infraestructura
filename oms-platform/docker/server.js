// ── server.js — PLACEHOLDER DE INFRAESTRUCTURA, NO ES EL OMS REAL ──────────
//
// El enunciado del trabajo (Trabajo - enunciado.md, sección 1) es explícito:
// "Tu trabajo en este bloque NO es implementar la aplicación —eso vendrá en
// bloques posteriores—. Tu trabajo es provisionar y operar la infraestructura
// que la va a alojar."
//
// Este archivo NO es la aplicación OMS. Es un servidor HTTP mínimo, sin
// dependencias de terceros (solo el módulo nativo "http" de Node.js),
// creado únicamente para poder:
//   1. Construir una imagen Docker real y obtener un `image_sha` válido
//      (Fase 3 del trabajo).
//   2. Que Cloud Run tenga algo real que ejecutar y sus startup/liveness
//      probes (modules/compute/main.tf) puedan pasar de verdad.
//   3. Que el health check del Load Balancer (regla de firewall
//      allow-lb-health-checks, modules/network/main.tf) reciba una
//      respuesta 200 real en el puerto 8080.
//
// No implementa NINGUNA lógica de negocio del dominio OMS (catálogo,
// pedidos, pagos, etc. — ver anexo-arquitectura/02-bounded-contexts.md).
//
// NOTA DE DISEÑO — hallazgo real durante la Fase 2 (ver
// BITACORA-COMANDOS.md): el endpoint se llama /health, NO /healthz.
// /healthz es interceptado por Google Front End (GFE) ANTES de llegar al
// contenedor en algunos productos serverless de GCP (convención histórica
// reservada internamente por Google) — las peticiones a /healthz nunca
// aparecían en los logs de Cloud Run, siempre devolvían un 404 genérico
// de Google, mientras que la raíz "/" sí funcionaba y sí quedaba
// registrada. Se optó por /health para evitar el conflicto.

const http = require('node:http');

const PORT = process.env.PORT || 8080;

// Cambio deliberadamente mínimo y sin riesgo (Fase 5, verificación completa
// del ciclo build → deploy staging → deploy producción con canary real →
// rollback): añade "version" al JSON de /health, únicamente para poder
// confirmar a simple vista qué revisión/imagen responde realmente tras
// cada despliegue. No cambia el status code, el content-type, ni la
// estructura base que ya validan las probes/healthchecks existentes.
//
// 0.3.0 (Fase 6, verificación real del workflow canary-decision.yml):
// mismo cambio sin riesgo, solo el número de versión, para generar un
// build nuevo y disparar el pipeline completo una vez más, dejando en
// producción un canary real al 10% sobre el que probar el workflow de
// decisión (promote/rollback) por primera vez desde GitHub Actions.
const BUILD_VERSION = '0.3.0';

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    // Endpoint que consultan: el HEALTHCHECK del Dockerfile, las
    // startup_probe/liveness_probe de Cloud Run, y los health checks
    // del Load Balancer (rangos de GFE permitidos por firewall).
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', version: BUILD_VERSION }));
    return;
  }

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    message: 'Placeholder de infraestructura — NO es la aplicación OMS real.',
    note: 'Ver Trabajo - enunciado.md sección 1: implementar la app no es parte de este bloque.',
  }));
});

server.listen(PORT, () => {
  // Log estructurado simple — el proyecto real usaría Pino (ver
  // referencia en la skill toscaprompt), pero aquí basta con confirmar
  // que el proceso arrancó, para depurar despliegues en Cloud Run.
  console.log(JSON.stringify({ event: 'server_started', port: PORT }));
});
