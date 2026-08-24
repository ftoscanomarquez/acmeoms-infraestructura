# ADR-004 · PostgreSQL único multi-AZ activo-pasivo, esquemas por módulo

## Estado
**Aceptada** · 2025-01-15

## Contexto

El monolito modular ([ADR-001](ADR-001-monolito-modular.md)) necesita una capa de persistencia que cumpla:

- **NFR-AVAIL-001** — checkout 99.9% mensual (≤ 43 min downtime)
- **NFR-AVAIL-002** — catálogo 99.95% mensual (≤ 22 min downtime)
- **OPS-005** — RTO ≤ 4h, RPO ≤ 1h
- **OPS-003** — presupuesto 800 €/mes (la BD se lleva una porción significativa, tope ~300 €/mes)
- **NFR-SEC-001** — PII cifrada en reposo (AES-256)
- **FR-001** — transacción atómica al crear pedido (reserva stock + autorizar pago + crear order + outbox)
- **NFR-PERF-002** — latencia p95 < 400ms en POST /api/orders (la BD es el cuello de botella habitual)
- **REG-GDPR-002** — derecho al olvido en ≤ 30 días (cascadas de borrado factibles)

Los seis módulos del monolito tienen necesidades de datos distintas pero compatibles con un motor relacional (no hay un caso que justifique NoSQL hoy).

> 💡 **NOTA · V2 — Trade-offs honestos**
> Hay tres tensiones en esta decisión: disponibilidad vs. coste, separación vs. consolidación, y rendimiento vs. consistencia. Vamos a tomar partido en cada una y dejar las contras explícitas.

## Decisión

**Una única instancia PostgreSQL gestionada (AWS RDS o equivalente)** con:

1. **Multi-AZ activo-pasivo** — primary en AZ1, standby síncrono en AZ2 con failover automático ante fallo del primary (típicamente < 60 segundos).
2. **Esquemas separados por módulo** — `catalog`, `inventory`, `orders`, `payments`, `billing`, `iam`, además de `shared` (Money, eventos) y `outbox`.
3. **Cifrado en reposo** — RDS encryption at rest con KMS, llaves rotadas anualmente.
4. **Cifrado adicional a nivel columna** para PII especialmente sensible (DNI, dirección postal completa).
5. **Backups automáticos** — snapshot diario + WAL archiving cada 5 min (RPO < 5 min, mejor que el exigido).
6. **Retención de backups** — 35 días (snapshots) + 7 años para los snapshots etiquetados como hito legal (facturación).
7. **Réplica de lectura** opcional para reportes pesados (módulo billing en cierres mensuales).
8. **Replicación cross-region asíncrona** a `eu-central-1` para disaster recovery — ver [ADR-007](ADR-007-regiones-despliegue.md).
9. **Connection pooling** con PgBouncer (transaction mode) para no agotar conexiones del primary.

**Acceso desde el monolito:**

- Cada módulo solo lee/escribe en su esquema. Esto se valida con permisos a nivel de PostgreSQL: el rol `app_oms` tiene `USAGE` en todos los esquemas pero `INSERT/UPDATE/DELETE` solo aparece en las migraciones (que son globales). Los tests de arquitectura adicionalmente verifican que las queries SQL en `adapters/persistence/` de cada módulo no referencian tablas de otro esquema.
- Las transacciones que cruzan esquemas (FR-001 toca `orders.*`, `inventory.*` y `outbox.*`) se permiten explícitamente desde el composition root del flujo.

## Consecuencias

### Positivas

- **ACID disponible para cualquier operación intra-monolito** — fundamental para FR-001.
- **Multi-AZ activo-pasivo cumple NFR-AVAIL-001** con holgura — failover < 60s, peor caso 2-3 minutos en mes.
- **Coste razonable** — RDS db.m6g.xlarge multi-AZ ~250 €/mes; encaja en presupuesto OPS-003.
- **Backups + WAL** cumplen OPS-005 con margen (RPO real ~5 min vs. exigido 1h).
- **Cifrado at rest** transparente cumple NFR-SEC-001 sin coste de implementación.
- **Esquemas separados** dan ownership claro a cada módulo; las migraciones se versionan por esquema.
- **Una sola BD para administrar** — un solo plan de backup, una sola monitorización, un solo tuning.
- **Migraciones de schema independientes por módulo** — el módulo orders puede añadir una tabla sin impactar a billing.

### Negativas

- **Acoplamiento físico** — si la instancia cae completamente (fallo de la AZ entera + standby), todos los módulos caen. Mitigación: ver [ADR-007](ADR-007-regiones-despliegue.md) para failover regional.
- **No permite SLAs distintos por módulo** — todos comparten la disponibilidad de la BD. Aceptable porque el SLA es uniforme (NFR-AVAIL-001 ≈ NFR-AVAIL-002).
- **Cuello de botella potencial en el primary** — todas las escrituras pasan por una sola instancia. Mitigación: monitorización de I/O y CPU; si se llega al 70% sostenido, escalar vertical.
- **Connection pool compartido** — el primary tiene un límite de conexiones. PgBouncer mitiga, pero hay que dimensionar.
- **Migraciones de BD requieren coordinación** — cuando se cambia el esquema, debe ser compatible hacia atrás durante el rolling deploy. Estrategia expand-and-contract (heredada del módulo de implementación).
- **Multi-AZ activo-pasivo NO es zero-downtime** — el failover tarda decenas de segundos. Para esto, tendríamos que ir a activo-activo, fuera de presupuesto.

## Alternativas descartadas

### A · Multi-AZ activo-activo (Aurora Multi-Master, dos primaries)

**Por qué se descartó:**
- Coste real ~3× la opción elegida (~750-900 €/mes solo en BD), excede OPS-003 considerando el resto de infraestructura.
- Activo-activo introduce complejidad por conflictos de escritura — para un sistema con 1.000 req/s pico, no merece la pena.
- 99.9% se cumple sobradamente con activo-pasivo; necesitaríamos 99.99% para que activo-activo aporte ROI claro.

### B · Una BD por módulo (6 instancias separadas)

**Por qué se descartó:**
- Coste 4-6× — fuera de presupuesto.
- Multiplica la operación: 6 backups, 6 monitorizaciones, 6 multi-AZ, 6 conjuntos de credenciales.
- Pierde transacciones ACID entre módulos — FR-001 (reserva atómica + creación pedido + outbox) se vuelve saga inmediatamente, contraviniendo [ADR-003](ADR-003-comunicacion-entre-modulos.md).
- Solo aporta valor real cuando un módulo necesita un motor diferente (Mongo, Cassandra), que no es el caso hoy.

### C · BD única sin esquemas separados (todo en `public`)

**Por qué se descartó:**
- Permitiría que cualquier módulo lea/escriba en tablas de otro → frontera de bounded context se erosiona en semanas.
- Imposibilita la extracción futura de un módulo a servicio independiente sin reescritura completa del acceso a datos.
- No tiene ventaja de coste (es la misma instancia).

### D · MongoDB / DynamoDB

**Por qué se descartó:**
- El dominio del OMS es relacional por naturaleza (pedidos con líneas, productos con categorías, facturas con desglose IVA). Modelar esto en documental introduce duplicación o joins de aplicación.
- Las restricciones de consistencia fuerte (FR-001) son más naturales en relacional.
- El equipo conoce PostgreSQL (criterio V2: familiaridad gana cuando las opciones son equivalentes en cumplir restricciones).

### E · MySQL en lugar de PostgreSQL

**Por qué se descartó:**
- Equivalente para nuestras necesidades.
- PostgreSQL elegido por familiaridad del equipo, mejor soporte de tipos avanzados (JSONB para snapshots y eventos), e idiomática más limpia para esquemas separados.

### F · CockroachDB / YugabyteDB (NewSQL)

**Por qué se descartó:**
- Sobreingeniería para 1K req/s pico. NewSQL aporta valor a partir de tamaños y latencias geográficas que no tenemos.
- Coste operativo más alto y menos ecosistema (tooling, observabilidad).

## Re-evaluación

Esta decisión se debe revisar cuando:

- El **primary llegue al 70% de CPU/IO sostenido** durante > 1 mes — primero escalar vertical, después considerar particionar (un módulo a su BD).
- Aparezca **un módulo con perfil de carga radicalmente distinto** (p. ej., catalog con búsquedas full-text que justifique Elasticsearch dedicado).
- **NFR-AVAIL-001 se eleve a 99.99%** — ahí sí toca activo-activo o multi-región síncrono, con su coste asociado.
- El **número de tablas por esquema** se vuelva inmanejable — señal de que el bounded context se ha vuelto demasiado grande y necesita partirse.

## Referencias

- ADR previos: [ADR-001](ADR-001-monolito-modular.md), [ADR-002](ADR-002-hexagonal-por-modulo.md), [ADR-003](ADR-003-comunicacion-entre-modulos.md)
- ADR siguiente: [ADR-005 · Redis caché de catálogo](ADR-005-redis-cache-catalogo.md)
- ADR siguiente: [ADR-007 · Regiones de despliegue](ADR-007-regiones-despliegue.md)

---

> 💡 **NOTA PEDAGÓGICA — Vídeo 2**
>
> Este ADR es un buen ejemplo de cómo un trade-off del Vídeo 2 se resuelve con datos. La opción "ideal" (activo-activo multi-región) y la "mínima viable" (single-AZ) son los extremos. La opción correcta es la que cumple las restricciones con margen sin reventar el presupuesto.
>
> Fíjate en algo importante: ningún número aquí está inventado. RDS multi-AZ activo-pasivo cuesta lo que cuesta, el failover tarda lo que tarda, los 99.9% se cumplen o no. Cuando documentes ADRs en proyectos reales, **busca y cita los números**. La intuición no vale.
