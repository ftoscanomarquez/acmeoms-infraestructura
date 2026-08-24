# 01 · Inventario de restricciones arquitectónicas

> **Entregable 1 de 4** — Aplicación del Vídeo 2, paso 1 (inventariar) y paso 2 (clasificar).
>
> **Input:** SRS del sistema OMS (módulo de Requisitos y Especificación).
> **Output:** todas las restricciones que condicionan decisiones arquitectónicas, clasificadas por tipo.

> 💡 **NOTA · V2 — Inputs arquitectónicos**
> Este es el primer paso del proceso de derivación. Antes de tomar UNA SOLA decisión arquitectónica, hay que tener todas las restricciones encima de la mesa. La regla del módulo: si una decisión no se puede trazar a una restricción de este inventario, esa decisión es arbitraria.

---

## 1 · Quality Attributes y NFRs cuantificados

> 💡 **NOTA · V1 — Decisiones costosas**
> Estos números son los que mandan sobre la arquitectura. Cambiar un NFR cuantificado típicamente invalida varios ADRs. Por eso hay que tenerlos antes de empezar.

### Rendimiento

| ID | Requisito | Condición de carga | Verificación |
|----|-----------|--------------------|--------------|
| **NFR-PERF-001** | `GET /api/products` (catálogo): latencia p95 < 150ms | 800 req/s sostenido | k6 load test, Prometheus p95 |
| **NFR-PERF-002** | `POST /api/orders` (crear pedido): latencia p95 < 400ms | 100 req/s incluyendo reserva de stock + pago | k6 + APM (tracing distribuido) |
| **NFR-PERF-003** | `GET /api/orders/:id` (consulta): latencia p95 < 200ms | 300 req/s | k6 load test |
| **NFR-PERF-004** | Búsqueda full-text en catálogo: latencia p95 < 300ms | dataset de 50K productos | k6 + Elasticsearch query log |

### Escalabilidad

| ID | Requisito | Verificación |
|----|-----------|--------------|
| **NFR-SCAL-001** | El sistema soporta pico de 5× sobre carga normal (Black Friday): de ~200 req/s a ~1.000 req/s sin degradación de NFR-PERF-* | Chaos test con simulación Black Friday |
| **NFR-SCAL-002** | Crecimiento orgánico de 30% anual sin redeploy mayor durante 3 años | Capacity planning trimestral |

### Disponibilidad

| ID | Requisito | Verificación |
|----|-----------|--------------|
| **NFR-AVAIL-001** | Checkout disponible 99.9% del tiempo medido mensualmente (≤ 43 min downtime/mes) | Uptime monitor externo (Pingdom) |
| **NFR-AVAIL-002** | Catálogo (lectura) disponible 99.95% (≤ 22 min downtime/mes) | Uptime monitor externo |
| **NFR-AVAIL-003** | Mantenimiento programado fuera de ventanas comerciales (12:00–22:00 hora local) | Calendario de releases |

### Seguridad

| ID | Requisito | Verificación |
|----|-----------|--------------|
| **NFR-SEC-001** | PII (nombre, email, dirección, teléfono) cifrada AES-256 en reposo | Auditoría de configuración + scan |
| **NFR-SEC-002** | Comunicación cliente-servidor con TLS 1.3 (TLS 1.2 mínimo aceptable) | SSL Labs A+ |
| **NFR-SEC-003** | Tokens de pago: tokenización delegada al PSP (no almacenamos PAN) | PCI-DSS SAQ-A |
| **NFR-SEC-004** | Autenticación con OAuth2 + refresh tokens; admins con MFA obligatorio | Test de penetración trimestral |

### Mantenibilidad / observabilidad

| ID | Requisito | Verificación |
|----|-----------|--------------|
| **NFR-MAINT-001** | Onboarding de un nuevo developer en ≤ 2 semanas hasta primera PR mergeada | Tracking en HR |
| **NFR-MAINT-002** | Cobertura de tests del dominio ≥ 85% | CI bloquea merge si baja |
| **NFR-MAINT-003** | Tracing distribuido end-to-end de cada request HTTP | OpenTelemetry + Tempo |
| **NFR-MAINT-004** | Logs estructurados (JSON) en stdout, agregados centralizadamente | ELK / Loki |

---

## 2 · Restricciones operativas

> 💡 **NOTA · V3 — Granularidad y equipo**
> Estas son las restricciones que más se ignoran y más decisiones acaban condicionando en la práctica. El tamaño del equipo y el presupuesto son las que hacen que microservicios sea suicidio en proyectos pequeños.

| ID | Restricción | Implicación arquitectónica esperada |
|----|-------------|-------------------------------------|
| **OPS-001** | Equipo: 8 developers + 2 SREs | Imposible operar microservicios con plataforma desde cero (V3) |
| **OPS-002** | Despliegues: solo 09:00–18:00 CET, no en viernes ni vísperas de festivo | No despliegues nocturnos ni en fin de semana — limita estrategias de zero-downtime |
| **OPS-003** | Presupuesto infraestructura: 800 €/mes | Descarta multi-AZ activo-activo (~1.500 €/mes) y plataforma de microservicios |
| **OPS-004** | Logs centralizados con retención de 90 días | Coste de Loki/ELK previsto en presupuesto |
| **OPS-005** | RTO ≤ 4 horas, RPO ≤ 1 hora | Backups diarios + WAL archiving suficiente; no replicación síncrona multi-región |
| **OPS-006** | Releases: 1-2 por semana en horario de oficina | Pipeline CI/CD con rollback automático y canary opcional |
| **OPS-007** | On-call: solo dos SREs, rotación semanal, no fines de semana fuera de incidente | Sistema debe degradar suavemente, no requerir intervención humana inmediata |

---

## 3 · Restricciones regulatorias

> 💡 **NOTA · V1 — Restricciones inflexibles**
> Las regulatorias no son negociables. Si la spec las nombra, el sistema TIENE que cumplirlas o no se lanza. La derivación arquitectónica de estas restricciones suele ser directa: una restricción → una decisión técnica concreta.

| ID | Regulación | Requisito técnico derivado |
|----|------------|----------------------------|
| **REG-GDPR-001** | Residencia de datos: PII de ciudadanos UE almacenada en regiones UE | Despliegue limitado a regiones europeas (eu-west-1, eu-central-1) |
| **REG-GDPR-002** | Derecho al olvido: borrar PII en ≤ 30 días tras solicitud | Job programado de borrado + cascada por bounded context + invalidación de caches |
| **REG-GDPR-003** | Audit trail inmutable de accesos a datos personales | Log append-only con retención mínima de 3 años |
| **REG-GDPR-004** | Consentimiento explícito y versionado para tratamiento de datos | Consent management con versionado y reconsent en cambios de política |
| **REG-GDPR-005** | Notificación de breach en ≤ 72h | Incident response runbook + monitorización de accesos anómalos |
| **REG-PCI-001** | No almacenar PAN, CVV ni datos sensibles de tarjeta en sistema propio | Tokenización delegada a PSP certificado (PCI-DSS Level 1) |
| **REG-PCI-002** | Datos de tarjeta nunca en logs (incluso parciales si entran en alcance) | Sanitización de logs automática + alertas si aparecen patrones de PAN |
| **REG-IVA-001** | Facturas con IVA conforme normativa española (Ley 37/1992 e IVA Inmediato si aplica) | Módulo de facturación con cálculo de IVA por tipo de producto y registros AEAT |
| **REG-IVA-002** | Numeración correlativa de facturas, conservación 4 años | Esquema de facturación con secuencia atómica + almacenamiento legal |

---

## 4 · Restricciones funcionales con impacto arquitectónico

> 💡 **NOTA · V2 — La spec puede decidir por ti**
> No todos los FR son arquitectónicamente neutros. Estos en particular condicionan decisiones porque introducen acoplamientos, asincronía o picos de carga.

| ID | Requisito funcional | Impacto arquitectónico |
|----|---------------------|-----------------------|
| **FR-001** | Crear pedido con reserva atómica de stock | Implica transaccionalidad entre módulo de pedidos y de stock — habilita o descarta separación en servicios |
| **FR-014** | Notificación email al cliente al confirmar pedido (en < 5 min) | Asincronía aceptable → eventos de dominio + worker de notificaciones |
| **FR-022** | Generación de factura PDF tras confirmar pedido | Generación pesada (PDF + sello legal) — separar del flujo síncrono del checkout |
| **FR-029** | Búsqueda full-text en catálogo con sugerencias | Índice especializado (Elasticsearch o equivalente) — separar de la BD operacional |
| **FR-038** | Exportar pedidos del usuario en formato CSV (data subject access) | Job asíncrono con notificación al estar listo |

---

## 5 · Asunciones explícitas

> 💡 **NOTA · V2 — Trazabilidad**
> Las asunciones también van en el inventario. Si una asunción se rompe, las decisiones derivadas pueden invalidarse. Documentarlas explícitamente protege al equipo de "pero yo daba por hecho que…".

- **A-001** — Stripe sigue ofreciendo tokenización con SAQ-A en regiones UE durante el horizonte del proyecto (3 años).
- **A-002** — El equipo crece ≤ 2 personas/año en los próximos 24 meses.
- **A-003** — El catálogo cambia ≤ 50 veces/día (justifica caché con TTL de minutos).
- **A-004** — La normativa fiscal española no introduce e-invoicing obligatorio para B2C antes de 2027 (asunción a vigilar).
- **A-005** — El proveedor de email transaccional (SendGrid o similar) tiene SLA ≥ 99.95%.

---

## Resumen ejecutivo del inventario

> 💡 **NOTA · V2 — Antes del paso 3**
> Tras inventariar y clasificar, el siguiente paso es derivar decisiones candidatas. Antes de seguir, comprobad que el inventario es completo. Si encontráis menos de 20 restricciones en una spec real, casi seguro hay cosas implícitas que no se han hecho explícitas.

**Total de restricciones inventariadas: 39**

| Categoría | Nº | Decisiones que tienden a generar |
|-----------|----|-----------------------------------|
| Rendimiento | 4 | Caching, indexación, materialización |
| Escalabilidad | 2 | Stateless services, autoscaling, mensajería |
| Disponibilidad | 3 | Multi-AZ, replicación, circuit breakers |
| Seguridad | 4 | Cifrado, autenticación, network segmentation |
| Mantenibilidad / observabilidad | 4 | Patrones de despliegue, observabilidad estructurada |
| Operativas | 7 | Granularidad, ventanas de despliegue, presupuesto |
| Regulatorias | 9 | Residencia de datos, audit trail, retention |
| Funcionales con impacto | 5 | Transaccionalidad, asincronía, índices especializados |
| Asunciones | 5 | A vigilar, no decisiones directas |

---

## Próximo entregable

→ **02-bounded-contexts.md** — descomposición del dominio en zonas coherentes (input para decidir granularidad y patrón interno).
