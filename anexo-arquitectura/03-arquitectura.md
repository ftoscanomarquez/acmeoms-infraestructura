# 03 · Documento de Arquitectura del OMS

> **Entregable 3 de 4** — Síntesis: la arquitectura concreta derivada de los inputs anteriores.
>
> **Inputs:** [01-inventario-restricciones](01-inventario-restricciones.md), [02-bounded-contexts](02-bounded-contexts.md).
> **Output:** vista de la arquitectura completa, justificada decisión a decisión.

> 💡 **NOTA · V1 — Arquitectura justificada vs. arbitraria**
> Este documento NO es un dibujo bonito que se inventó alguien. Cada caja, cada flecha, cada decisión tiene detrás un ADR con su trazabilidad a una restricción concreta. Si alguien añade un componente que no está justificado por una restricción, lo borramos.

---

## 1 · Resumen ejecutivo

| Aspecto | Decisión | ADR |
|---------|----------|-----|
| **Granularidad** | Monolito modular con 6 módulos | [ADR-001](05-adrs/ADR-001-monolito-modular.md) |
| **Patrón interno** | Hexagonal (Ports & Adapters) por módulo | [ADR-002](05-adrs/ADR-002-hexagonal-por-modulo.md) |
| **Comunicación** | Síncrona vía puertos in-process + event bus interno | [ADR-003](05-adrs/ADR-003-comunicacion-entre-modulos.md) |
| **Persistencia** | PostgreSQL único multi-AZ activo-pasivo, esquemas por módulo | [ADR-004](05-adrs/ADR-004-postgresql-multi-az.md) |
| **Caché** | Redis read-through delante del catálogo | [ADR-005](05-adrs/ADR-005-redis-cache-catalogo.md) |
| **Pagos** | Stripe (tokenización delegada, alcance PCI reducido) | [ADR-006](05-adrs/ADR-006-stripe-tokenizacion.md) |
| **Despliegue** | eu-west-1 (primary) + eu-central-1 (DR) | [ADR-007](05-adrs/ADR-007-regiones-despliegue.md) |
| **Frontend** | SPA estática servida por CDN | [ADR-008](05-adrs/ADR-008-frontend-spa-cdn.md) |
| **Eventos** | Outbox pattern para entrega fiable | [ADR-009](05-adrs/ADR-009-outbox-pattern.md) |
| **Cumplimiento GDPR** | Audit trail inmutable + workflow de borrado | [ADR-010](05-adrs/ADR-010-audit-trail-gdpr.md) |

---

## 2 · Diagrama de componentes (vista lógica)

```
                                ┌──────────────────────────────┐
                                │       USUARIOS FINALES       │
                                │     (navegador, móvil)       │
                                └──────────────┬───────────────┘
                                               │ HTTPS
                                               ▼
                                ┌──────────────────────────────┐
                                │      CDN  (CloudFront)       │  ← ADR-008
                                │  - SPA estática (assets)     │
                                │  - imágenes de productos     │
                                └──────────┬─────────┬─────────┘
                                           │         │
                                  GET API  │         │ static
                                           ▼         ▼ (cache)
                                ┌──────────────────────────────┐
                                │   API Gateway / Load Balancer│
                                │  - TLS 1.3 termination       │
                                │  - rate limiting             │
                                │  - WAF (anti-DDoS / bot)     │
                                └──────────────┬───────────────┘
                                               │
            ┌──────────────────────────────────┼──────────────────────────────────┐
            │                                  │                                  │
            ▼                                  ▼                                  ▼
   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │                         MONOLITO MODULAR — OMS app                              │ ← ADR-001
   │                       (Node.js/TS o Java/Spring Boot)                           │
   │                                                                                 │
   │   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
   │   │   Catalog    │  │  Inventory   │  │   Orders     │  │   Payments   │       │
   │   │  (módulo)    │  │  (módulo)    │  │  (módulo)    │  │  (módulo)    │       │
   │   │              │  │              │  │              │  │              │       │
   │   │ ports + adap │  │ ports + adap │  │ ports + adap │  │ ports + adap │       │
   │   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
   │          │                 │                 │                 │               │
   │          │                 ▼                 ▼                 │               │
   │          │       ┌─────────────────────────────────────┐       │               │
   │          │       │   Event Bus interno (in-process)    │       │ ← ADR-003     │
   │          │       │   + Outbox table (PostgreSQL)       │ ← ADR-009             │
   │          │       └─────────────────────────────────────┘       │               │
   │          │                                                     │               │
   │   ┌──────┴───────┐  ┌──────────────┐                           │               │
   │   │   Billing    │  │     IAM      │                           │               │
   │   │  (módulo)    │  │  (módulo)    │                           │               │
   │   │              │  │              │                           │               │
   │   │ ports + adap │  │ ports + adap │                           │               │
   │   └──────────────┘  └──────────────┘                           │               │
   │                                                                │               │
   │   composition-root (main.ts / Application.java) ──────────────┘               │
   └─────────────────────────────┬───────────────────┬───────────────────────────────┘
                                 │                   │
              read-through       │                   │  HTTPS (SDK)
                                 ▼                   ▼
                       ┌──────────────────┐  ┌──────────────────┐
                       │   Redis (caché)  │  │     Stripe       │ ← ADR-006
                       │   - catálogo     │  │   (PSP externo)  │
                       └────────┬─────────┘  └──────────────────┘
                                │
                                │ miss → DB
                                ▼
                       ┌────────────────────────────────────┐
                       │   PostgreSQL (multi-AZ a/p)        │ ← ADR-004
                       │                                    │
                       │   esquemas: catalog, inventory,    │
                       │   orders, payments, billing, iam   │
                       │                                    │
                       │   + esquema 'outbox' para eventos  │
                       │   + audit_log (append-only)        │ ← ADR-010
                       └────────────────────────────────────┘
                                │
                                │ replicación async cross-region
                                ▼
                       ┌────────────────────────────────────┐
                       │   PostgreSQL DR (eu-central-1)     │
                       │   réplica + standby                │
                       └────────────────────────────────────┘
```

---

## 3 · Vista de despliegue (eu-west-1)

> 💡 **NOTA · V3 — Stateless + autoescalado**
> El monolito está empaquetado como contenedor stateless. Esto permite cumplir NFR-SCAL-001 (pico 5×) escalando réplicas horizontalmente. La sesión vive en JWT (cliente) y el estado de carrito en Redis con TTL — el contenedor de aplicación no guarda nada en memoria entre requests.

```
                eu-west-1 (Irlanda — región primaria)
   ┌──────────────────────────────────────────────────────────────────┐
   │                                                                  │
   │   ┌──────────────────────────────────────────┐                   │
   │   │       AZ 1                               │                   │
   │   │                                          │                   │
   │   │  ┌──────────────┐    ┌──────────────┐    │                   │
   │   │  │ App pod #1   │    │ App pod #2   │    │                   │
   │   │  │  (monolito)  │    │  (monolito)  │    │                   │
   │   │  └──────────────┘    └──────────────┘    │                   │
   │   │                                          │                   │
   │   │  PostgreSQL primary (single writer)      │                   │
   │   │  Redis primary                            │                   │
   │   └──────────────────────────────────────────┘                   │
   │                          │                                       │
   │                          │ replicación síncrona                  │
   │                          ▼                                       │
   │   ┌──────────────────────────────────────────┐                   │
   │   │       AZ 2 (passive failover)            │                   │
   │   │  PostgreSQL standby (sync)               │                   │
   │   │  Redis replica                            │                   │
   │   │  App pods adicionales (autoscaling)      │                   │
   │   └──────────────────────────────────────────┘                   │
   └──────────────────────────────────────────────────────────────────┘
                          │
                          │ replicación async
                          ▼
                eu-central-1 (Frankfurt — DR)        ← ADR-007
   ┌──────────────────────────────────────────────────────────────────┐
   │   PostgreSQL standby (async)                                     │
   │   App pods en cold standby                                       │
   │   Activación manual con runbook (RTO 4h)                         │
   └──────────────────────────────────────────────────────────────────┘
```

---

## 4 · Estructura de código (proyecto)

> 💡 **NOTA · V4, V5 — La estructura habla**
> La organización de carpetas debería hacer evidente la arquitectura sin necesidad de un documento adicional. Aquí cualquier developer ve `src/modules/<bc>/{domain,adapters}` y entiende inmediatamente: ese módulo aplica hexagonal.

```
oms/
├── src/
│   ├── modules/
│   │   ├── catalog/
│   │   │   ├── domain/
│   │   │   │   ├── entities/        Product.ts, Category.ts
│   │   │   │   ├── value-objects/   Price.ts, ProductSlug.ts
│   │   │   │   ├── usecases/        ListProductsUseCase.ts, GetProductUseCase.ts
│   │   │   │   └── ports/
│   │   │   │       ├── driving/     CatalogQueries.ts
│   │   │   │       └── driven/      ProductRepository.ts, ProductCache.ts
│   │   │   ├── adapters/
│   │   │   │   ├── http/            catalogRouter.ts
│   │   │   │   └── persistence/     PostgresProductRepository.ts, RedisProductCache.ts
│   │   │   └── module.ts            (composition: instancia adapters + use cases)
│   │   │
│   │   ├── inventory/  (mismo patrón)
│   │   ├── orders/     (mismo patrón)
│   │   ├── payments/   (mismo patrón)
│   │   ├── billing/    (mismo patrón)
│   │   └── iam/        (mismo patrón)
│   │
│   ├── shared/
│   │   ├── domain/
│   │   │   ├── value-objects/       Money.ts, UserId.ts, OrderId.ts (Shared Kernel)
│   │   │   └── events/              DomainEvent.ts, EventBus.ts
│   │   ├── adapters/
│   │   │   └── outbox/              OutboxPublisher.ts, OutboxRelay.ts
│   │   └── infra/
│   │       ├── http/                Express setup, error handler
│   │       ├── persistence/         Postgres pool, migrations
│   │       └── observability/       OpenTelemetry, structured logger
│   │
│   └── main.ts                       composition root
│
├── tests/
│   ├── domain/         (tests unitarios por módulo, sin BD)
│   ├── integration/    (tests con InMemory implementations)
│   └── e2e/            (suite completa con BD real, en CI)
│
├── infra/
│   ├── docker/         Dockerfile, docker-compose.yml (dev)
│   ├── k8s/            manifests / Helm chart
│   ├── terraform/      AWS RDS, ElastiCache, ECS/EKS
│   └── runbooks/       failover.md, restore-from-backup.md, gdpr-deletion.md
│
└── docs/
    ├── 05-adrs/           ADR-001..010 (este proyecto)
    ├── api/            OpenAPI spec
    └── architecture/   este documento + diagramas
```

---

## 5 · Vista de comunicación entre módulos

### 5.1 Flujo síncrono — crear pedido

```
Cliente → API Gateway → orders.OrderController
                         │
                         ▼
                    orders.CreateOrderUseCase
                         │
                         ├─► catalog.ProductInfoProvider          (síncrono, in-process)
                         │     └─ snapshot del producto + precio
                         │
                         ├─► inventory.StockReserver               (síncrono, in-process)
                         │     └─ reservar stock atómicamente
                         │
                         ├─► payments.PaymentGateway               (síncrono, externo a Stripe)
                         │     └─ autorizar cobro (no captura todavía)
                         │
                         ▼
                    orders.OrderRepository.save(order)             (PostgreSQL)
                         │
                         ▼
                    publish(OrderCreated) → outbox table
                         │
                         ▼
                    OutboxRelay → Event Bus interno
                                       │
                                       ├─► billing (genera factura, async)
                                       └─► (notificaciones email, async)
```

> 💡 **NOTA · V3 — Una transacción ACID**
> Todo el flujo de creación de pedido (reserva stock + autorizar pago + crear order + escribir outbox) ocurre en una **única transacción ACID** porque vivimos en un monolito modular. En microservicios esto sería una saga con compensaciones — más complejo, más casos a gestionar.

### 5.2 Flujo asíncrono — confirmar pedido (tras pago capturado)

```
payments — captura pago tras autorizar
   │
   ▼
publish(PaymentCaptured) → outbox → Event Bus
                                       │
                                       ▼
                                  orders.handlePaymentCaptured
                                       │
                                       ▼
                                  Order.confirm() — transición PENDING → CONFIRMED
                                       │
                                       ▼
                                  publish(OrderConfirmed) → outbox → Event Bus
                                                                       │
                                          ┌────────────────────────────┼─────────────────────────────┐
                                          ▼                            ▼                             ▼
                                     inventory                       billing                  notifications
                                  (consolida reservas)           (genera factura)             (email cliente)
```

---

## 6 · Vista de capas (cada módulo)

> 💡 **NOTA · V4, V5 — La regla de la dependencia**
> Dentro de cada módulo, las dependencias apuntan hacia adentro. Las flechas en este diagrama van siempre desde adapters hacia el dominio, nunca al revés.

```
   ┌──────────────────────────────────────────────────────────────────┐
   │                            Frameworks                            │
   │   Express, pg, Redis client, Stripe SDK, otros                   │
   └──────────────────────┬───────────────────────────────────────────┘
                          ▼ (dependencia)
   ┌──────────────────────────────────────────────────────────────────┐
   │                      Interface Adapters                          │
   │                                                                  │
   │   driving/                          driven/                      │
   │   ─ HTTP controllers                ─ Postgres repositories      │
   │   ─ Queue consumers                 ─ Stripe gateway             │
   │   ─ Event handlers                  ─ Redis cache                │
   │   ─ CLI                             ─ Email sender               │
   └──────────────────────┬───────────────────────────────────────────┘
                          ▼ (dependencia hacia adentro)
   ┌──────────────────────────────────────────────────────────────────┐
   │                    Use Cases (Application)                       │
   │                                                                  │
   │   ─ CreateOrderUseCase, CancelOrderUseCase                       │
   │   ─ Definen los puertos que necesitan                            │
   │   ─ Reciben implementaciones por inyección                       │
   └──────────────────────┬───────────────────────────────────────────┘
                          ▼ (dependencia hacia adentro)
   ┌──────────────────────────────────────────────────────────────────┐
   │                     Entities (Domain)                            │
   │                                                                  │
   │   ─ Order, OrderItem, Product, StockItem, Invoice...             │
   │   ─ Reglas de negocio (Order.cancel(), Order.total())            │
   │   ─ Value objects (Money, OrderId, ProductSlug)                  │
   │   ─ CERO imports de frameworks                                   │
   └──────────────────────────────────────────────────────────────────┘
```

---

## 7 · Decisiones operativas

### 7.1 Despliegue

> 💡 **NOTA · V3, OPS-002 — Ventanas de cambio**
> OPS-002 dice "despliegues solo 09:00–18:00 CET, no en viernes". Esto descarta migraciones que requieran horas, y empuja a hacer rolling updates con health checks. → ADR-006 (deploy strategy heredado del módulo de implementación).

- **Pipeline:** GitHub Actions (build → tests → image → staging → manual approval → prod)
- **Estrategia:** rolling update con `maxSurge=25%` + readiness/liveness probes
- **Rollback:** automático si error rate > 5% durante 5 min tras deploy
- **Migraciones de BD:** estrategia expand-and-contract (compatibilidad backwards durante 2 releases)

### 7.2 Observabilidad

| Concepto | Herramienta | NFR cumplido |
|----------|-------------|--------------|
| Logs estructurados | Loki (ingesta JSON desde stdout) | NFR-MAINT-004 |
| Métricas | Prometheus + Grafana | NFR-PERF-001..004 |
| Tracing distribuido | OpenTelemetry → Tempo | NFR-MAINT-003 |
| Alertas | Alertmanager → PagerDuty | OPS-007 |
| Uptime monitoring | Pingdom externo | NFR-AVAIL-001..003 |

### 7.3 Seguridad operativa

- **Secretos:** AWS Secrets Manager, rotación automática trimestral
- **Cifrado en reposo:** AES-256 a nivel de RDS y S3 (transparent encryption)
- **Cifrado en tránsito:** TLS 1.3 (TLS 1.2 mínimo para clientes legacy)
- **Network:** VPC privada, RDS y Redis sin IPs públicas, security groups restrictivos
- **Auditoría:** CloudTrail para AWS + audit_log propio para datos de negocio

### 7.4 Backup y disaster recovery

| Política | Implementación | Cumple |
|----------|---------------|--------|
| Backup BD | snapshot diario + WAL archiving | OPS-005 (RPO ≤ 1h) |
| Retención backups | 35 días | OPS-005 |
| Test de restauración | ejercicio mensual en staging | OPS-005 |
| Failover regional | runbook manual, switchover DNS | OPS-005 (RTO ≤ 4h) |

---

## 8 · Trazabilidad: matriz restricción ↔ decisión

> 💡 **NOTA · V1, V2 — Sin esta matriz no hay arquitectura justificada**
> Esta es la prueba de fuego: cada restricción del inventario aparece justificando al menos una decisión, y cada decisión cita al menos una restricción. Si una restricción queda sin decisión, no la cumplimos. Si una decisión no cita restricción, es arbitraria.

| Restricción | Decisión que la cumple | ADR |
|-------------|------------------------|-----|
| NFR-PERF-001 | Caché Redis del catálogo | ADR-005 |
| NFR-PERF-002 | Transacción ACID single-DB + tracing distribuido | ADR-001, ADR-004 |
| NFR-PERF-003 | Índice por `userId` en orders.orders + caché opcional | ADR-004 |
| NFR-PERF-004 | Elasticsearch como índice de búsqueda (módulo catalog) | (ADR posterior, no en este documento) |
| NFR-AVAIL-001 | Multi-AZ activo-pasivo + rolling deploy con health checks | ADR-004 |
| NFR-AVAIL-002 | Caché Redis sirve catálogo aunque DB falle parcialmente | ADR-005 |
| NFR-AVAIL-003 | Ventanas de despliegue codificadas en pipeline | ADR-001 |
| NFR-SCAL-001 | App stateless + autoescalado + Redis para sesiones de carrito | ADR-001 |
| NFR-SCAL-002 | Capacidad headroom 30% en infra base | ADR-001 |
| NFR-SEC-001 | RDS encryption at rest + cifrado columna PII | ADR-004 |
| NFR-SEC-002 | TLS 1.3 en API Gateway | ADR-007 (despliegue) |
| NFR-SEC-003 | Stripe tokenización delegada | ADR-006 |
| NFR-SEC-004 | OAuth2 + MFA admin (módulo IAM) | (config IAM) |
| NFR-MAINT-001 | Hexagonal por módulo + estructura predecible | ADR-002 |
| NFR-MAINT-002 | Tests de dominio rápidos (cobertura > 85%) | ADR-002 |
| NFR-MAINT-003 | OpenTelemetry instrumentación | (config observability) |
| NFR-MAINT-004 | Logger estructurado JSON | (config observability) |
| OPS-001 | Monolito modular (no microservicios) | ADR-001 |
| OPS-002 | Pipeline con ventanas restringidas | ADR-001 |
| OPS-003 | Multi-AZ activo-pasivo (no activo-activo) | ADR-004 |
| OPS-004 | Loki / ELK con retención 90d | (config observability) |
| OPS-005 | Backups + WAL archiving + replica DR | ADR-004, ADR-007 |
| OPS-006 | Pipeline CI/CD con rolling + rollback | (config CI) |
| OPS-007 | Sistema degrada suavemente (circuit breakers) | ADR-002 |
| REG-GDPR-001 | Despliegue solo eu-west-1 + eu-central-1 | ADR-007 |
| REG-GDPR-002 | Workflow de borrado en cascada en 30d | ADR-010 |
| REG-GDPR-003 | Audit trail inmutable | ADR-010 |
| REG-GDPR-004 | Consent management con versionado | (módulo IAM) |
| REG-GDPR-005 | Incident response runbook + alertas | (runbooks) |
| REG-PCI-001 | Stripe tokenización (alcance PCI reducido) | ADR-006 |
| REG-PCI-002 | Sanitización automática de logs | (config observability) |
| REG-IVA-001 | Módulo billing con cálculo IVA | (impl. módulo billing) |
| REG-IVA-002 | InvoiceNumber correlativo + retención 4 años | (impl. módulo billing) |
| FR-001 | Transacción ACID atómica en monolito | ADR-001 |
| FR-014 | Eventos de dominio + worker de notificaciones | ADR-003, ADR-009 |
| FR-022 | Generación factura asíncrona vía evento | ADR-003 |
| FR-029 | Elasticsearch como índice de búsqueda | (ADR posterior) |
| FR-038 | Job asíncrono de export | ADR-010 |

**Cobertura: 39/39 restricciones del inventario tienen decisión documentada.**

---

## 9 · Vistas no incluidas (fuera de alcance de este módulo)

Para no contaminar este entregable de Arquitectura derivada, las siguientes vistas y decisiones se documentan en módulos posteriores del máster:

- **Estrategia de testing detallada** (módulo de implementación)
- **Estrategia de release y feature flags** (módulo de operación)
- **Modelo de datos físico detallado** (módulo de modelado)
- **Capacity planning detallado** (módulo de SRE)

---

## Próximo entregable

→ **05-adrs/** — un ADR por cada decisión clave. Y luego la **04-revision-cruzada.md** que valida la coherencia del conjunto.
