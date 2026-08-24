# ADR-007 · Despliegue en eu-west-1 + DR en eu-central-1

## Estado
**Aceptada** · 2025-01-15

## Contexto

El sistema OMS debe cumplir:

- **REG-GDPR-001** — datos personales de ciudadanos UE almacenados en regiones UE
- **NFR-AVAIL-001** — checkout 99.9% mensual
- **OPS-005** — RTO ≤ 4h, RPO ≤ 1h
- **OPS-003** — presupuesto 800 €/mes (descarta multi-región activo-activo síncrono)

El producto se vende exclusivamente en España; los clientes están geográficamente concentrados, lo que limita el beneficio de tener réplicas globales.

> 💡 **NOTA · V1 — Restricciones inflexibles**
> REG-GDPR-001 es la restricción que más fuerte condiciona esta decisión. Los datos personales de ciudadanos UE NO pueden almacenarse en regiones de Estados Unidos, Asia, etc. Esto descarta de raíz cualquier topología "global" típica.

## Decisión

Topología **single-region activo + región DR pasiva**:

### Región primaria: `eu-west-1` (Irlanda)

- **App pods** en al menos dos AZs (multi-AZ activo) con autoescalado horizontal.
- **PostgreSQL primary** en AZ-1 con standby síncrono en AZ-2 (ver [ADR-004](ADR-004-postgresql-multi-az.md)).
- **Redis primary** en AZ-1 con replica asíncrona en AZ-2.
- **API Gateway / ALB** distribuye tráfico entre AZs.
- **CloudFront** sirve la SPA y assets estáticos (ver [ADR-008](ADR-008-frontend-spa-cdn.md)).
- **Webhook Stripe** entra a través del mismo ALB.

### Región DR: `eu-central-1` (Frankfurt)

- **PostgreSQL standby asíncrono** — replica desde el primary de eu-west-1 con lag típico < 10s, peor caso ~1 minuto.
- **Configuración de infraestructura preparada** (Terraform + AMIs) pero **app pods en cold standby** (creados solo durante el ejercicio de DR o ante incidente real).
- **Backups cross-region** del bucket de S3 (snapshots, audit logs).

### Activación del DR

Manual, ejecutada con **runbook documentado** (`infra/runbooks/regional-failover.md`):

1. SRE de guardia recibe alerta de "región eu-west-1 indisponible > 30 min".
2. Decisión humana de activar DR (incident commander).
3. Promote del standby de PostgreSQL en eu-central-1 a primary.
4. Provisión de pods de aplicación apuntando al nuevo primary.
5. Cambio de DNS (Route 53) para apuntar el dominio público a eu-central-1.
6. Comunicación al cliente: "modo degradado posible durante X min, transacciones reanudadas".

**Tiempo objetivo:** RTO de 4 horas (con margen — el ejercicio mensual demuestra que se puede hacer en 1-2 horas).

### Ejercicios

- **Ejercicio mensual** de restauración de backup en staging (válido para verificar RPO).
- **Ejercicio trimestral** de simulacro de failover regional en staging (con runbook completo).
- **Ejercicio anual** de failover real en producción durante ventana programada de baja actividad.

## Consecuencias

### Positivas

- **REG-GDPR-001 cumplido** — todas las regiones (primaria y DR) están en UE; los datos nunca cruzan fuera.
- **NFR-AVAIL-001 cumplido** con holgura para fallos típicos (multi-AZ); para fallos catastróficos de región hay DR.
- **OPS-005 cumplido** — RTO ≤ 4h con runbook probado, RPO ≤ 1h con replicación cross-region asíncrona.
- **Coste razonable** — la región DR cuesta ~30% adicional sobre la primaria (replica de BD asíncrona + storage). Total ~70-80 €/mes extra. Encaja en presupuesto.
- **Topología simple** — un solo lugar al que apuntar tráfico habitualmente; sin balanceo geográfico ni cuestiones de "qué región atiende a quién".

### Negativas

- **Failover regional NO automático** — requiere intervención humana. Esto es una decisión consciente: un failover automático mal disparado por un falso positivo puede causar más downtime del que evita.
- **Pods de aplicación en cold standby** — en caso de DR, hay que provisionar capacidad. Mitigación: AMIs y Helm charts pre-construidos; tiempo de provisión < 30 min con Terraform.
- **Latencia adicional para clientes alemanes / centroeuropeos** durante DR — atendidos desde eu-central-1 que es local para ellos, pero todavía con lag de "modo emergencia". Aceptable porque el negocio es España-centric.
- **Replicación asíncrona = posible pérdida de datos** en una ventana de hasta ~1 minuto en caso de pérdida total de eu-west-1. RPO 1h se cumple holgadamente.
- **Sin presencia en otras regiones del mundo** — si el negocio expande a US o LATAM, esto requerirá replantearse (multi-región con sharding por jurisdicción).

## Alternativas descartadas

### A · Multi-región activo-activo (eu-west-1 + eu-central-1 como peers)

**Por qué se descartó:**
- Coste 2-3× — fuera de presupuesto OPS-003.
- Replicación síncrona cross-region introduce latencias (~50ms+ entre Frankfurt y Dublin) que afectarían NFR-PERF-002.
- Conflict resolution en escrituras concurrentes añade complejidad operativa significativa.
- ROI solo aparece si necesitamos disponibilidad > 99.99% — no es el caso.

### B · Single-region sin DR (solo multi-AZ)

**Por qué se descartó:**
- En caso de fallo de toda la región (raro pero no imposible), recovery sería desde backups offsite — RTO no cumpliría OPS-005.
- Reputación: un outage prolongado tiene coste de imagen muy superior al de la replica DR.
- AWS ha tenido al menos un incidente regional de > 4h en los últimos años; estamos por encima de ese umbral.

### C · Multi-región pero con eu-south-2 (Madrid)

**Por qué se considera y se descarta hoy:**
- Latencia hacia España sería ligeramente mejor (~5-10ms vs. eu-west-1).
- Sin embargo, eu-south-2 tiene menos servicios disponibles (ej. cobertura de instancias gestionadas, ElastiCache, etc.) y es más reciente (estabilidad operativa).
- eu-west-1 es la región AWS más madura en Europa, con SLA y características más estables.
- Cuando eu-south-2 madure (~2026 según roadmap), reconsiderar como primaria con eu-west-1 como DR.

### D · Activo-activo pero solo entre AZs (sin DR cross-region)

**Por qué se descartó:**
- AZ failover ya está cubierto por multi-AZ (ADR-004).
- Sin DR cross-region, un fallo regional total nos deja sin recovery razonable. OPS-005 exige RTO 4h, lo cual no es alcanzable solo con backups en otra región sin infra preparada.

### E · DR caliente (warm standby) en lugar de cold

**Por qué se descartó (por ahora):**
- Reduciría RTO de 4h a < 30 min.
- Coste: ~80% de la región primaria (pods running, no cold).
- Para el SLA actual (99.9%), 4h de RTO es suficiente. Si aumentamos a 99.99%, esta decisión se reabre.

## Re-evaluación

Esta decisión se debe revisar cuando:

- **NFR-AVAIL-001 se eleve a 99.99%** — habría que ir a warm standby o activo-activo.
- El **negocio expanda fuera de España** — replantear topología (potencialmente multi-región activa con sharding por jurisdicción legal).
- **eu-south-2 (Madrid) alcance madurez operativa** — reconsiderar como primaria.
- Aparezca **regulación que prohíba transferencia de datos personales entre estados UE** (improbable pero a vigilar).
- El **ejercicio de DR mensual revele tiempos de recovery > 2h** — actualizar runbook o automatizar pasos manuales.

## Referencias

- ADR previos: [ADR-001](ADR-001-monolito-modular.md), [ADR-004](ADR-004-postgresql-multi-az.md)
- Runbook: `infra/runbooks/regional-failover.md`
- Restricciones cumplidas: REG-GDPR-001, NFR-AVAIL-001, OPS-005

---

> 💡 **NOTA PEDAGÓGICA — Vídeo 2**
>
> Este ADR es un ejemplo claro del trade-off del Vídeo 2: una restricción regulatoria (REG-GDPR-001) FUERZA la decisión a una de muy pocas opciones (regiones UE). Dentro del subconjunto válido, otras restricciones (presupuesto, RTO/RPO) seleccionan la topología concreta.
>
> Lección operativa: **el failover automático no siempre es mejor que el manual**. Un script que activa DR cuando ve un timeout puede reaccionar a un blip de red y meter al sistema en un loop. Aquí se decide explícitamente humano-en-el-loop, lo cual añade RTO pero reduce falsos positivos. Es la decisión correcta para un equipo de 2 SREs.
