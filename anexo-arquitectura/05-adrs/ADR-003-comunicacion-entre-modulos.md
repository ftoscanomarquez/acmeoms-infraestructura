# ADR-003 · Comunicación entre módulos: puertos síncronos + event bus interno

## Estado
**Aceptada** · 2025-01-15

## Contexto

Tras decidir [monolito modular](ADR-001-monolito-modular.md) con [hexagonal por módulo](ADR-002-hexagonal-por-modulo.md), queda definir **cómo se comunican los módulos entre sí** dentro del proceso.

El [context map](../02-bounded-contexts.md#relaciones-entre-contextos-context-map) identifica dos tipos de relaciones:

- **Síncronas con resultado inmediato:** `Orders → Inventory.reserveStock()`, `Orders → Payments.authorize()`, `Orders → Catalog.getProductSnapshot()`
- **Asíncronas / reactivas:** `Inventory ← OrderConfirmed`, `Billing ← OrderConfirmed`, `Notifier ← OrderConfirmed`

Restricciones que aplican:

- **NFR-PERF-002** — `POST /api/orders` p95 < 400ms (no podemos hacer cosas pesadas síncronamente)
- **FR-001** — crear pedido con reserva atómica de stock (transaccionalidad)
- **FR-014** — notificación email en < 5 min (asincronía aceptable)
- **FR-022** — generación de factura (asincronía aceptable, no bloquea checkout)
- **NFR-MAINT-001** — onboarding rápido (no quemar gente con sagas innecesarias)

> 💡 **NOTA · V6 — Aggregates y consistencia**
> Una de las reglas de DDD: una transacción modifica un solo aggregate. Pero esa regla aplica a la consistencia _eventual_ entre aggregates, no a la atomicidad del flujo. En un monolito modular tenemos la posibilidad de envolver varios aggregates en una transacción ACID — y la usamos cuando el dominio lo exige (FR-001), aceptando el ligero acoplamiento.

## Decisión

Usamos **dos modos** de comunicación entre módulos:

### Modo 1 · Síncrono vía puerto del dominio

Para operaciones donde el llamante necesita el resultado inmediatamente (validar, decidir).

```typescript
// orders/domain/ports/driven/StockReserver.ts
export interface StockReserver {
  reserve(orderId: OrderId, items: OrderItem[]): Promise<ReservationResult>;
}

// inventory/module.ts (composition)
const stockReserver: StockReserver = new InventoryStockReserver(inventoryService);

// orders/module.ts
const createOrderUseCase = new CreateOrderUseCase(
  orderRepo,
  stockReserver,  // ← inyectado, no importa de qué módulo viene
  paymentGateway,
);
```

**Características:**
- Llamada a método in-process (latencia µs).
- El consumidor (Orders) define la interfaz que necesita; el proveedor (Inventory) la implementa.
- Participa en la transacción ACID si hay una abierta.

### Modo 2 · Asíncrono vía evento de dominio

Para operaciones donde el publicador no necesita el resultado o donde la consistencia es eventual.

```typescript
// orders/domain/events/OrderConfirmed.ts
export class OrderConfirmed {
  constructor(
    public readonly orderId: OrderId,
    public readonly userId: UserId,
    public readonly items: ReadonlyArray<{productId: ProductId; quantity: number}>,
    public readonly total: Money,
    public readonly occurredAt: Date,
  ) {}
}

// orders persiste el evento en outbox dentro de la misma transacción que el aggregate
// → ver ADR-009 sobre el outbox pattern

// inventory/adapters/queue/OrderEventsConsumer.ts
async handleOrderConfirmed(event: OrderConfirmed) {
  for (const item of event.items) {
    await this.stock.confirmReservation(event.orderId, item.productId, item.quantity);
  }
}

// billing/adapters/queue/OrderEventsConsumer.ts
async handleOrderConfirmed(event: OrderConfirmed) {
  await this.invoiceGenerator.generate(event.orderId, event.userId, event.items, event.total);
}
```

**Características:**
- Eventually consistent: el suscriptor reacciona "poco después" del publicador (segundos).
- Múltiples suscriptores pueden reaccionar al mismo evento sin conocerse entre sí.
- La entrega se garantiza con [outbox pattern](ADR-009-outbox-pattern.md).

### Reglas inviolables

1. **Los módulos NO acceden a tablas de otros módulos directamente.** Si Orders necesita info de Catalog, llama a `ProductInfoProvider`. Nunca hace `SELECT` sobre `catalog.products`.
2. **Las llamadas síncronas pasan por puertos explícitos** definidos en el dominio del consumidor.
3. **Los eventos llevan datos suficientes** para que los suscriptores reaccionen sin volver a consultar al publicador.
4. **Sin ciclos de eventos.** Un módulo no se suscribe a eventos que provocaría su propia acción. Si lo necesita, repensar el diseño.
5. **Los eventos persisten en outbox** dentro de la misma transacción que el aggregate origen, garantizando atomicidad y entrega exactly-once efectivo.
6. **Los nombres de eventos van en pasado** (`OrderConfirmed`, no `ConfirmOrder`). Un comando es intención; un evento es hecho.

## Consecuencias

### Positivas

- **Bajo acoplamiento entre módulos** — cambiar internals de Inventory no afecta a Orders mientras se respete el contrato del puerto.
- **Múltiples suscriptores** sin modificar el publicador — añadir notificaciones SMS es solo añadir un nuevo consumidor.
- **Migración futura a servicios independientes** factible — los puertos ya existen, los eventos ya circulan; basta sustituir el bus interno por una cola externa.
- **Transaccionalidad disponible cuando se necesita** (modo síncrono dentro de un BEGIN/COMMIT en PostgreSQL).
- **Asincronía donde aporta valor** (FR-014, FR-022) sin sobrecargar el flujo síncrono.

### Negativas

- **Más boilerplate** que llamadas directas entre clases internas. Coste real: ~10-15 líneas adicionales por puerto. Pago: cada vez que extraes un módulo o cambias proveedores.
- **Eventual consistency en flujos reactivos** — un cliente puede ver el pedido confirmado antes de que la factura esté generada. Mitigación: documentar explícitamente y, si hay UX que lo requiera, hacer polling o WebSocket.
- **Más complejidad operativa** — el outbox y el relay son nuevos componentes a observar (ver ADR-009).
- **Riesgo de eventos huérfanos** si no se mantiene disciplina (eventos que nadie consume durante meses pero siguen publicándose).

## Alternativas descartadas

### A · Llamadas directas a clases internas de otros módulos

**Por qué se descartó:**
- Rompería los bounded contexts en el primer mes.
- Hace imposible la extracción futura a servicios.
- Acopla por implementación, no por contrato.

### B · Cola externa (RabbitMQ / Kafka) desde el día 1

**Por qué se descartó:**
- Innecesario para comunicación in-process. Latencia µs vs. ms, sin ganancia.
- Coste operativo adicional (una cola más que mantener) sin justificación: el sistema solo tiene un proceso.
- Cuando Orders → Stripe necesita una cola (anti-corruption + retry), eso ya es comunicación con sistema externo, no inter-módulo.

### C · Solo síncrono (sin eventos)

**Por qué se descartó:**
- FR-014 (notificaciones email) y FR-022 (facturas) son lentos — los meter en el flujo síncrono mete latencia y propagación de fallo.
- Sin eventos no hay desacoplamiento de suscriptores: añadir uno nuevo requiere modificar al publicador.

### D · Solo asíncrono (eventual consistency en todo)

**Por qué se descartó:**
- FR-001 exige reserva atómica de stock — sin transacción ACID, el cliente podría confirmar un pedido y dos minutos después recibir un error de "stock no disponible".
- Sagas + compensaciones en un equipo de 10 personas son contraproducentes (V3).

### E · Comandos in-process via mensajería (in-memory bus para todo)

**Por qué se descartó:**
- Un command bus añade indirección sin beneficio cuando el llamante necesita el resultado síncrono.
- Hace los flujos más opacos al debugging (pierdes el stack trace).

## Re-evaluación

Esta decisión se debe revisar cuando:

- Un módulo se **extraiga a servicio independiente** — ahí los puertos sincrónicos se vuelven HTTP/gRPC, y el event bus interno se sustituye por una cola externa.
- Aparezcan **picos de eventos > 10K/seg** que el bus interno no aguante (improbable en este sistema).
- La **complejidad del outbox** se vuelva un problema mantener (en ese caso, evaluar event store dedicado).

## Referencias

- ADR previos: [ADR-001](ADR-001-monolito-modular.md), [ADR-002](ADR-002-hexagonal-por-modulo.md)
- ADR siguiente: [ADR-009 · Outbox pattern](ADR-009-outbox-pattern.md)
- Context map: [02-bounded-contexts.md](../02-bounded-contexts.md#relaciones-entre-contextos-context-map)

---

> 💡 **NOTA PEDAGÓGICA — Vídeos 6 y 7**
>
> El Vídeo 6 (DDD) introduce los Domain Events. El Vídeo 7 (gestión de dependencias) explica por qué los puertos invertidos rompen los ciclos.
>
> Los dos modos coexisten porque resuelven problemas distintos:
> - **Síncrono con puerto** = quiero el resultado AHORA y necesito que la transacción agrupe varias operaciones.
> - **Evento** = quiero que otros módulos reaccionen sin que yo me entere de quiénes son.
>
> El error típico que vemos en clase es usar uno donde toca el otro: meter notificaciones email en el flujo síncrono (rompe NFR-PERF-002), o meter "reservar stock" como evento (rompe FR-001 al introducir eventual consistency donde el dominio exige atomicidad).
