# ADR-008 · Frontend SPA estática servida por CDN

## Estado
**Aceptada** · 2025-01-15

## Contexto

El frontend del OMS necesita servir:

- Catálogo navegable (rendimiento crítico — NFR-PERF-001)
- Carrito y checkout (interactivo)
- Cuenta de usuario y historial de pedidos
- Imágenes de productos (~50K productos × 3-5 imágenes cada uno = ~200-250K assets)

Restricciones:

- **NFR-PERF-001** — `GET /api/products` p95 < 150ms (la API debería responder rápido, pero la UI también debe ser perceptiblemente rápida — first paint < 1.5s)
- **NFR-AVAIL-002** — catálogo 99.95% (el cliente debe poder navegar incluso en mantenimiento programado breve)
- **OPS-003** — presupuesto 800 €/mes
- **NFR-SEC-002** — TLS 1.3
- Audiencia geográficamente concentrada en España (latencia local importa)

## Decisión

Frontend como **Single Page Application (SPA) estática** servida por **CDN (CloudFront o equivalente)**, con la API REST del monolito como backend.

### 1 · Stack del frontend

- **Framework:** React + TypeScript (decisión de equipo, fuera del alcance del módulo de Arquitectura derivada).
- **Build:** Vite produce assets estáticos (`index.html`, JS bundles, CSS, imágenes).
- **Hosting:** S3 bucket privado, accedido vía CloudFront con OAI (Origin Access Identity).
- **Distribución:** CloudFront con edge locations en Europa.

### 2 · Política de caché en el CDN

| Asset | Cache-Control | TTL en CDN |
|-------|---------------|-----------|
| `index.html` | `no-cache` | 0 (siempre fresca) |
| JS / CSS bundles con hash en el nombre | `public, max-age=31536000, immutable` | 1 año |
| Imágenes de productos | `public, max-age=86400` | 1 día (con invalidación al cambiar producto) |
| Fuentes web | `public, max-age=31536000, immutable` | 1 año |

El hash en el nombre de los bundles (Vite lo añade automáticamente, ej. `app.4f8a9c.js`) permite invalidación implícita: el deploy nuevo cambia el hash, el `index.html` (no cacheado) referencia el nuevo bundle.

### 3 · Rutas

- **`/api/*`** → ALB del monolito (no pasa por CDN).
- **Resto** → CDN sirve la SPA.
- **CORS** configurado en el monolito permitiendo solo el dominio de la SPA.
- **CSP (Content Security Policy)** restrictiva en `index.html`: solo permite scripts de nuestro dominio + Stripe.

### 4 · TLS

- **TLS 1.3** en CloudFront (con TLS 1.2 fallback para clientes legacy).
- **HSTS** habilitado con preload.
- **Certificate** vía ACM (renovación automática).

### 5 · Server-side rendering: NO

Decisión explícita: la SPA renderiza en cliente. Justificación:

- SEO no es prioridad para checkout y áreas privadas (la mayoría de tráfico).
- Las páginas públicas SEO-relevantes (landing, catálogo top) se pre-renderizan estáticamente en build (SSG selectivo) si fuera necesario en el futuro. Por ahora, no implementado.
- Añadir SSR convierte el frontend en otro servicio runtime que mantener.

## Consecuencias

### Positivas

- **First paint extremadamente rápido** desde edge locations cercanas al cliente (España → Madrid edge ~5-10ms).
- **Reduce carga sobre el monolito** — los assets estáticos ni rozan la app.
- **Mejora NFR-AVAIL-002** — incluso si el monolito está en mantenimiento programado breve, la SPA se sirve desde CDN. El cliente puede navegar (con datos cacheados) hasta que el catálogo vuelva.
- **Coste mínimo** — CloudFront cobra por GB transferido. Estimación: ~30-50 €/mes para nuestro tráfico.
- **Escalado automático infinito** del frontend (el CDN escala lo que haga falta).
- **DDoS mitigation** "gratis" en el edge — CloudFront absorbe ataques antes de llegar a la app.
- **TLS 1.3 nativo** en CloudFront sin coste adicional de implementación.

### Negativas

- **No SEO out-of-the-box** — la primera carga es JS-intensive. Aceptable para áreas privadas; las áreas públicas tendrían que añadir pre-rendering si SEO se vuelve crítico.
- **Bundle inicial relativamente grande** — la SPA carga JS + CSS antes del primer render. Mitigación: code splitting por ruta, lazy loading.
- **Caché stale possible** — un usuario con `index.html` en caché del navegador puede ejecutar una versión antigua de la SPA durante minutos. Mitigación: `no-cache` para `index.html` + bundles hasheados.
- **Invalidación de imágenes de productos** requiere disparar invalidación CDN al cambiar producto — procesado por el módulo `catalog`.
- **CORS necesario** entre dominio de SPA y dominio de API — un poco más de configuración pero no problema operativo serio.

## Alternativas descartadas

### A · Server-Side Rendering (Next.js, Nuxt, Remix)

**Por qué se descartó:**
- Convierte el frontend en otro proceso runtime — más infraestructura, más despliegues, más cosas que monitorizar.
- Beneficios SEO no aportan valor crítico hoy (la mayoría del tráfico es post-login).
- Si SEO se vuelve crítico, la solución es pre-renderizar las landing pages estáticamente (SSG), no SSR completo.

### B · App tradicional con renderizado en el monolito (ej. server-side templates)

**Por qué se descartó:**
- Acopla el frontend al ciclo de release del monolito (cualquier cambio HTML requiere redeploy del backend).
- Desperdicia las características de los frameworks modernos (interactividad, code splitting, optimizaciones del navegador).
- Mete carga estática en la app (waste of resources).

### C · Frontend en monorepo con backend (en el mismo repo)

**Por qué se considera y se acepta parcialmente:**
- El frontend vive en `frontend/` dentro del mismo repo del monolito (decisión de DX, no de arquitectura).
- El **build y despliegue** son independientes: pipeline separado, artefactos separados, ciclo de release distinto.

### D · Servir todo desde el ALB del monolito (sin CDN)

**Por qué se descartó:**
- Latencia geográfica peor para clientes lejos de Dublin.
- Sobrecarga el ALB con tráfico estático (caro y desperdicio).
- Sin DDoS protection del edge.

### E · Cloudflare en lugar de CloudFront

**Por qué se considera:**
- Equivalente técnicamente, posiblemente con mejores precios para nuestro volumen.
- Decisión por ecosistema: si el resto de infra es AWS, mantenerlo simplifica IAM y networking.
- Cloudflare es la alternativa de respaldo si los precios de CloudFront se vuelven prohibitivos.

## Re-evaluación

Esta decisión se debe revisar cuando:

- El **SEO de catálogo público se vuelva crítico** para el negocio — implementar SSG selectivo o reconsiderar SSR.
- El **bundle inicial supere ~500KB gzipped** — síntoma de que el code splitting no está funcionando, evaluar lazy loading agresivo.
- Aparezca un **edge computing case** (ej. personalización geográfica fuerte) que requiera lógica en el edge — entonces evaluar Cloudflare Workers o CloudFront Functions.

## Referencias

- ADR previos: [ADR-001](ADR-001-monolito-modular.md), [ADR-004](ADR-004-postgresql-multi-az.md)
- Restricciones cumplidas: NFR-PERF-001 (UI), NFR-AVAIL-002, NFR-SEC-002, OPS-003

---

> 💡 **NOTA PEDAGÓGICA — Vídeo 2**
>
> Este ADR ilustra que **no toda decisión arquitectónica es crítica de alto coste**. Servir la SPA desde CDN es una decisión arquitectónica (afecta a despliegue, observabilidad, política de cache) pero su coste de revertir es bajo: cambiar de CDN o ir a SSR es trabajo de un sprint, no de un trimestre.
>
> Aún así, se documenta como ADR porque:
> 1. Otros developers verán el sistema y entenderán por qué está así.
> 2. Si dentro de 6 meses alguien pregunta "¿por qué no SSR?", la respuesta está aquí (no requiere reabrir debate).
> 3. La trazabilidad a NFRs y restricciones ayuda a saber cuándo replantear.
>
> Lección: **documenta decisiones cuyo "por qué" no es obvio en el código**. No documentes lo trivial. Esta línea es subjetiva — más vale documentar de más que arrepentirse en 6 meses.
