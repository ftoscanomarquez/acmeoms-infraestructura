# 02 · Mapa de Bounded Contexts

> **Entregable 2 de 4** — Aplicación del Vídeo 6 (DDD pragmático).
>
> **Input:** dominio del OMS según los FRs del SRS.
> **Output:** descomposición del dominio en zonas coherentes con relaciones explícitas entre ellas.

> 💡 **NOTA · V6 — Por qué empezamos por aquí**
> Antes de decidir granularidad de despliegue (monolito vs. microservicios) o patrón interno (hexagonal vs. capas), necesitamos saber cuántos modelos de dominio coherentes tenemos. Un bounded context puede acabar siendo un módulo dentro del monolito hoy y un servicio independiente mañana — pero la decisión de qué constituye un contexto debe ser estable.

---

## Vista general

El sistema OMS se descompone en **6 bounded contexts**:

```
┌──────────────────────────────────────────────────────────────────────┐
│                         OMS — Order Management System                │
│                                                                      │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐             │
│  │   Catalog    │   │   Inventory  │   │     IAM      │             │
│  │              │   │              │   │   (Identity  │             │
│  │ Productos,   │   │ SKU, stock,  │   │   & Access)  │             │
│  │ categorías,  │   │ ubicación,   │   │              │             │
│  │ precios      │   │ reservas     │   │ Usuarios,    │             │
│  │              │   │              │   │ sesiones,    │             │
│  │              │   │              │   │ permisos     │             │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘             │
│         │                  │                  │                     │
│         │ snapshot         │ reserve          │ identity            │
│         ▼                  ▼                  ▼                     │
│  ┌─────────────────────────────────────────────────────┐           │
│  │                       Orders                        │           │
│  │  Pedido, líneas, estado, transiciones, total        │ ◄──── núcleo del dominio
│  └────────────────┬────────────────────┬───────────────┘           │
│                   │                    │                           │
│                   │ OrderConfirmed     │ ChargeRequest             │
│                   ▼                    ▼                           │
│            ┌──────────────┐    ┌──────────────────┐               │
│            │   Billing    │    │     Payments     │               │
│            │              │    │                  │               │
│            │ Factura,     │    │ Tokenización,    │               │
│            │ IVA,         │    │ cobro, refund    │               │
│            │ correlativo  │    │ (delegado a PSP) │               │
│            │ AEAT         │    │                  │               │
│            └──────────────┘    └──────────────────┘               │
└──────────────────────────────────────────────────────────────────────┘
```

> 💡 **NOTA · V6 — La regla de oro**
> Cada contexto tiene su propio modelo coherente. El concepto "Producto" en `Catalog` (nombre, descripción, precio, fotos) es **distinto** del concepto "Producto" en `Inventory` (SKU, ubicación física, stock, dimensiones). Mismo nombre, modelos completamente distintos. Si los unificáramos, tendríamos una clase monstruo con cuarenta campos contradictorios.

---

## Cada contexto en detalle

### 1 · Catalog (Catálogo)

**Responsabilidad:** lo que el cliente ve cuando navega.

**Entidades / Value Objects principales:**

| Tipo | Nombre | Notas |
|------|--------|-------|
| Aggregate Root | `Product` | id, slug, nombre, descripción, precio, IVA aplicable, imágenes, categoría |
| Entity | `Category` | árbol de categorías |
| Value Object | `Price` (Money + IVA) | inmutable, comparable estructuralmente |
| Value Object | `ProductSlug` | URL-friendly, único |

**Eventos publicados:**

- `ProductCreated(productId, name, price, …)`
- `ProductUpdated(productId, changes)`
- `ProductDeactivated(productId, reason)`
- `PriceChanged(productId, oldPrice, newPrice, effectiveAt)`

**Eventos a los que reacciona:** ninguno (es un contexto que principalmente publica).

**Dependencias hacia otros contextos:** ninguna directa. Recibe stock como información proyectada (vía evento de Inventory).

> 💡 **NOTA · V6 — Aggregates pequeños**
> `Product` es un aggregate pequeño: solo gestiona los datos del catálogo, no su stock (eso es `StockItem` en Inventory). Esto evita locks largos al actualizar precios.

---

### 2 · Inventory (Inventario / Stock)

**Responsabilidad:** SKUs, stock disponible, reservas atómicas, ubicación física en almacén.

**Entidades / Value Objects principales:**

| Tipo | Nombre | Notas |
|------|--------|-------|
| Aggregate Root | `StockItem` | productId (referencia por ID a Catalog), available, reserved, total |
| Entity | `Reservation` | id, orderId, productId, quantity, status (HELD / CONFIRMED / RELEASED), expiresAt |
| Value Object | `Quantity` | entero ≥ 0, operaciones aritméticas validadas |
| Value Object | `WarehouseLocation` | almacén + pasillo + estante (no expuesto al cliente) |

**Eventos publicados:**

- `StockReserved(reservationId, orderId, productId, quantity)`
- `StockReleased(reservationId, reason)` — al cancelar pedido o expirar reserva
- `StockReplenished(productId, newAvailable)`
- `StockDepleted(productId)` — cuando available = 0

**Eventos a los que reacciona:**

- `OrderConfirmed` → consolida reservas (HELD → CONFIRMED)
- `OrderCancelled` → libera reservas (HELD → RELEASED)

**Dependencias hacia otros contextos:** referencia a `productId` por ID. **No accede a tablas de Catalog directamente.** Si necesita el nombre del producto, consulta la API pública de Catalog.

> 💡 **NOTA · V6 — Referencias por ID**
> `StockItem` referencia `productId` como string, no como objeto `Product`. Si necesitamos info del producto, llamamos al port `ProductInfoProvider`. Esto desacopla los contextos y permite que evolucionen independientemente. → ver [ADR-003](05-adrs/ADR-003-comunicacion-entre-modulos.md).

---

### 3 · Orders (Pedidos) — núcleo del dominio

**Responsabilidad:** ciclo de vida del pedido. Es el contexto más rico en reglas de negocio.

**Entidades / Value Objects principales:**

| Tipo | Nombre | Notas |
|------|--------|-------|
| Aggregate Root | `Order` | id, userId, items, status, total, createdAt, paymentId, deliveryAddress |
| Entity | `OrderItem` | productId, productSnapshot, quantity, unitPrice, subtotal |
| Value Object | `OrderId` | UUID v4 |
| Value Object | `OrderStatus` | enum: DRAFT, PENDING, CONFIRMED, PAID, SHIPPED, DELIVERED, CANCELLED, RETURNED |
| Value Object | `Money` (compartido vía Shared Kernel) | amount + currency |
| Value Object | `DeliveryAddress` | country, postal code, city, street, recipient |

**Reglas de negocio que viven aquí:**

- `Order.canBeCancelled() ↔ status ∈ {DRAFT, PENDING, CONFIRMED}`
- `Order.confirm() requiere status = PENDING ∧ stockReservation completada ∧ payment authorized`
- `Order.total() = Σ items[i].subtotal()` (invariante)
- Mínimo 1 item para confirmar; máximo 100 items por pedido (anti-fraude)

**Eventos publicados:**

- `OrderCreated(orderId, userId, items, total)` — al pasar a PENDING
- `OrderConfirmed(orderId, userId, items, total, paymentId, occurredAt)` — al pasar a CONFIRMED
- `OrderCancelled(orderId, userId, reason)`
- `OrderShipped(orderId, trackingNumber)`
- `OrderDelivered(orderId, deliveredAt)`

**Eventos a los que reacciona:**

- `StockReserved` → confirma reserva en flujo de creación
- `PaymentAuthorized` → desbloquea transición PENDING → CONFIRMED
- `PaymentFailed` → cancela el pedido y libera reservas

**Dependencias hacia otros contextos:**

- `Inventory` (puerto `StockReserver`)
- `Payments` (puerto `PaymentGateway`)
- `Catalog` (puerto `ProductInfoProvider` — para snapshot al crear el pedido)
- `IAM` (puerto `UserDirectory` — para validar y enriquecer datos de envío)

> 💡 **NOTA · V6 — Snapshot de productos**
> El `OrderItem` guarda un `productSnapshot` (nombre, precio en el momento de la compra). Esto es importante: si el precio del producto cambia mañana, los pedidos antiguos deben mantener el precio que pagó el cliente. El snapshot es la forma de modelar tiempo en aggregates.

---

### 4 · Payments (Pagos)

**Responsabilidad:** tokenización, autorización, captura, reembolsos. **Delegado a un PSP** (Stripe).

**Entidades / Value Objects principales:**

| Tipo | Nombre | Notas |
|------|--------|-------|
| Aggregate Root | `PaymentIntent` | id, orderId, amount, status (REQUESTED / AUTHORIZED / CAPTURED / FAILED / REFUNDED), pspReference |
| Value Object | `PaymentMethodToken` | token opaco devuelto por el PSP, NO almacenamos PAN |
| Value Object | `Money` (Shared Kernel) | |

**Eventos publicados:**

- `PaymentAuthorized(paymentId, orderId, amount, pspReference)`
- `PaymentCaptured(paymentId, orderId, amount, capturedAt)`
- `PaymentFailed(paymentId, orderId, errorCode, message)`
- `PaymentRefunded(paymentId, orderId, refundedAmount)`

**Eventos a los que reacciona:**

- `OrderConfirmed` → captura el pago previamente autorizado

**Patrón:** Anti-Corruption Layer (ACL) sobre Stripe — el modelo del PSP no contamina el modelo de dominio.

> 💡 **NOTA · V5 — Hexagonal en acción**
> `Payments` es un caso de libro de hexagonal: el puerto `PaymentGateway` está definido en el dominio con tipos del dominio (`Money`, `ChargeResult`), y la implementación `StripePaymentGateway` (driven adapter) traduce entre Stripe y el dominio. Si mañana migramos a Adyen, escribimos `AdyenPaymentGateway` y nada en `Orders` se entera. → ver [ADR-006](05-adrs/ADR-006-stripe-tokenizacion.md).

---

### 5 · Billing (Facturación)

**Responsabilidad:** factura legal española, IVA, numeración correlativa, conservación 4 años.

**Entidades / Value Objects principales:**

| Tipo | Nombre | Notas |
|------|--------|-------|
| Aggregate Root | `Invoice` | id (UUID interno), invoiceNumber (correlativo legal), orderId, lines, taxBreakdown, totalGross, totalNet, totalTax, issuedAt |
| Entity | `InvoiceLine` | description, quantity, unitPrice, taxRate, taxAmount |
| Value Object | `InvoiceNumber` | secuencia atómica anual, formato YYYY-NNNNNN |
| Value Object | `TaxBreakdown` | desglose por tipo de IVA (general, reducido, súper reducido, exento) |

**Eventos publicados:**

- `InvoiceIssued(invoiceId, invoiceNumber, orderId, totalGross, issuedAt)`
- `InvoiceCancelled(invoiceId, reason)` — solo permitido para casos legales muy específicos

**Eventos a los que reacciona:**

- `OrderConfirmed` → emite factura asíncronamente

**Patrón:** consumidor de eventos. El módulo es eventually consistent con `Orders` — la factura se genera en segundos, no es síncrona.

> 💡 **NOTA · V6 — Consistencia eventual entre aggregates**
> Una de las reglas del Vídeo 6: una transacción modifica un solo aggregate. La consistencia entre `Order` (en Orders) y `Invoice` (en Billing) es eventual, vía evento. Si el sistema de facturación está caído 30 segundos, los pedidos se siguen creando, y las facturas se generan cuando vuelve.

---

### 6 · IAM (Identity & Access Management)

**Responsabilidad:** registro y autenticación de usuarios, perfiles, sesiones, autorización por roles.

**Entidades / Value Objects principales:**

| Tipo | Nombre | Notas |
|------|--------|-------|
| Aggregate Root | `User` | id, email, passwordHash, profile, roles, mfaEnabled, createdAt |
| Aggregate Root | `Session` | id, userId, refreshToken, deviceInfo, expiresAt |
| Value Object | `Email` | validación + normalización |
| Value Object | `Role` | enum: CUSTOMER, ADMIN, BACKOFFICE_OPERATOR |

**Eventos publicados:**

- `UserRegistered(userId, email, registeredAt)`
- `UserDataExportRequested(userId, requestedAt)` — gateway al flujo GDPR
- `UserDataDeletionRequested(userId, requestedAt)` — gateway al flujo GDPR
- `UserDeleted(userId, deletedAt)` — tras completar el borrado en cascada

**Eventos a los que reacciona:** ninguno.

**Patrón:** core supplier — varios contextos dependen de él para identidad.

> 💡 **NOTA · V6 — Bounded context = posible servicio futuro**
> IAM es un candidato natural para extraer a un servicio aparte si el sistema crece, porque es el más independiente y tiene SLAs propios (auth ≠ catálogo). Por ahora vive como módulo dentro del monolito → ver [ADR-001](05-adrs/ADR-001-monolito-modular.md).

---

## Relaciones entre contextos (Context Map)

> 💡 **NOTA · V6 — Patrones de DDD para relaciones**
> Cada arista entre contextos tiene un nombre en DDD: Shared Kernel, Customer-Supplier, Conformist, Anti-Corruption Layer (ACL), Open Host Service (OHS), Published Language. No os ahoguéis en la teoría — lo importante es que la frontera sea explícita.

| De → A | Tipo de relación | Mecanismo concreto |
|--------|------------------|--------------------|
| Orders → Inventory | Customer-Supplier (síncrono) | Llamada al puerto `StockReserver`; Inventory dicta el contrato |
| Orders → Payments | Customer-Supplier (síncrono) | Llamada al puerto `PaymentGateway` |
| Orders → Catalog | Customer-Supplier (síncrono) | Lectura de `ProductInfoProvider` para snapshot |
| Orders → IAM | Conformist | IAM es upstream; Orders se adapta al modelo de User que dicta IAM |
| Inventory → Orders | Subscriber (asíncrono) | Suscrito a `OrderConfirmed` y `OrderCancelled` |
| Billing → Orders | Subscriber (asíncrono) | Suscrito a `OrderConfirmed` |
| Payments → external Stripe | ACL | `StripePaymentGateway` traduce el modelo de Stripe al modelo de Payments |
| Catalog ↔ Inventory | Shared Kernel mínimo | Comparten solo `productId` como tipo común; nada más |
| Todos los contextos | Shared Kernel | `Money`, `UserId`, `OrderId` (Value Objects compartidos) |

---

## Mapeo a módulos del monolito

> 💡 **NOTA · V3 — Granularidad**
> Los bounded contexts NO se traducen 1:1 a microservicios obligatoriamente. En el OMS los implementamos como **6 módulos dentro de un monolito modular**, con esquemas separados en PostgreSQL y APIs internas explícitas. → ver [ADR-001](05-adrs/ADR-001-monolito-modular.md) y [ADR-002](05-adrs/ADR-002-hexagonal-por-modulo.md).

| Bounded Context | Módulo | Esquema BD | Tipo |
|-----------------|--------|------------|------|
| Catalog | `catalog` | `catalog.*` | Lectura intensiva, cacheable |
| Inventory | `inventory` | `inventory.*` | Concurrencia alta (reservas) |
| Orders | `orders` | `orders.*` | Núcleo del dominio, lógica rica |
| Payments | `payments` | `payments.*` | ACL sobre Stripe, sin almacenar PAN |
| Billing | `billing` | `billing.*` | Eventually consistent con Orders |
| IAM | `iam` | `iam.*` | Datos sensibles (PII), cifrado at rest |

---

## Decisiones que dependen de este mapa

Este entregable es input directo de las siguientes decisiones (ADRs):

- [ADR-001 · Monolito modular](05-adrs/ADR-001-monolito-modular.md) — los bounded contexts son los módulos del monolito.
- [ADR-002 · Hexagonal por módulo](05-adrs/ADR-002-hexagonal-por-modulo.md) — cada bounded context tiene sus puertos y adapters.
- [ADR-003 · Comunicación entre módulos](05-adrs/ADR-003-comunicacion-entre-modulos.md) — el context map dicta qué es síncrono y qué es por evento.
- [ADR-009 · Outbox pattern](05-adrs/ADR-009-outbox-pattern.md) — los eventos del dominio deben entregarse fiablemente.

---

## Próximo entregable

→ **03-arquitectura.md** — documento de arquitectura con diagrama de componentes y todas las decisiones derivadas.
