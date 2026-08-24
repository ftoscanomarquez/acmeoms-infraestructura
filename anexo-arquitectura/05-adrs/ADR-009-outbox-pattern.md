# ADR-009 · Outbox pattern para entrega fiable de eventos del dominio

## Estado
**Aceptada** · 2025-01-15

## Contexto

[ADR-003](ADR-003-comunicacion-entre-modulos.md) establece que los módulos se comunican por eventos cuando la consistencia es eventual. El problema clásico:

**Si el evento se publica tras un commit a la BD, ¿qué pasa si el publish falla?** El aggregate quedó persistido pero los suscriptores nunca se enteran. Y a la inversa: si publicas antes del commit y el commit falla, los suscriptores reaccionan a un evento que "no ocurrió".

El sistema OMS necesita garantías de entrega fiables porque varios flujos críticos dependen de eventos:

- `OrderConfirmed` → activa generación de factura (FR-022, requisito legal de IVA)
- `OrderConfirmed` → consolida reserva de stock (FR-001, integridad de inventario)
- `PaymentCaptured` → desbloquea estado del pedido (FR-001)
- `UserDataDeletionRequested` → activa workflow GDPR (REG-GDPR-002, plazo legal de 30 días)

Una factura no emitida porque "se perdió un evento" es deuda legal. Un stock no liberado porque "se perdió un evento" es producto vendido dos veces.

> 💡 **NOTA · V6 — Domain Events y persistencia**
> En el Vídeo 6 vimos los Domain Events conceptualmente: nombres en pasado, inmutables, datos suficientes. La pregunta operativa es: **¿cómo garantizar que se entregan?** El outbox pattern es la respuesta canónica en sistemas con BD relacional.

## Decisión

Implementar **Transactional Outbox Pattern**:

### 1 · Esquema

Tabla `outbox.events` en PostgreSQL:

```sql
CREATE TABLE outbox.events (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type  text NOT NULL,             -- 'Order', 'Payment', etc.
    aggregate_id    text NOT NULL,             -- el ID del aggregate origen
    event_type      text NOT NULL,             -- 'OrderConfirmed', 'PaymentCaptured', ...
    payload         jsonb NOT NULL,            -- el evento serializado
    occurred_at     timestamptz NOT NULL DEFAULT now(),
    published_at    timestamptz,               -- NULL hasta publicación
    attempts        int NOT NULL DEFAULT 0,
    last_error      text
);

CREATE INDEX outbox_events_unpublished_idx
  ON outbox.events (occurred_at)
  WHERE published_at IS NULL;
```

### 2 · Escritura del evento (publisher)

El módulo que genera el evento lo escribe en `outbox.events` **dentro de la misma transacción** que la modificación del aggregate:

```typescript
// orders/adapters/persistence/PostgresOrderRepository.ts
async save(order: Order, events: DomainEvent[]): Promise<Order> {
  await this.db.transaction(async (tx) => {
    await tx.query('INSERT INTO orders.orders ... ', [...]);
    for (const event of events) {
      await tx.query(
        `INSERT INTO outbox.events
           (aggregate_type, aggregate_id, event_type, payload)
         VALUES ($1, $2, $3, $4)`,
        ['Order', order.id.value, event.constructor.name, JSON.stringify(event)]
      );
    }
  });
  return order;
}
```

**Atomicidad garantizada:** o se persisten ambos (aggregate + evento) o ninguno.

### 3 · Relay (publisher al bus interno)

Un componente `OutboxRelay` corre como worker en el monolito:

```typescript
class OutboxRelay {
  // cada 500ms
  async tick() {
    const events = await this.db.query(`
      SELECT id, payload, event_type
      FROM outbox.events
      WHERE published_at IS NULL
        AND attempts < 10
      ORDER BY occurred_at
      LIMIT 100
      FOR UPDATE SKIP LOCKED
    `);

    for (const event of events) {
      try {
        await this.eventBus.publish(event.event_type, event.payload);
        await this.db.query(
          'UPDATE outbox.events SET published_at = now() WHERE id = $1',
          [event.id]
        );
      } catch (e) {
        await this.db.query(
          `UPDATE outbox.events
              SET attempts = attempts + 1, last_error = $2
            WHERE id = $1`,
          [event.id, e.message]
        );
      }
    }
  }
}
```

**Características:**

- `FOR UPDATE SKIP LOCKED` permite múltiples relays concurrentes (en multi-réplica) sin doble entrega.
- **Backoff implícito:** un evento que falla 10 veces se marca para revisión manual (alerta a SRE).
- **Idempotencia obligatoria en consumidores** (siguiente sección).

### 4 · Idempotencia en consumidores

Los suscriptores deben tolerar **at-least-once delivery**: el mismo evento puede entregarse más de una vez si el relay crashea entre publish y mark-as-published.

Patrón estándar:

```typescript
class BillingOrderHandler {
  async handleOrderConfirmed(event: OrderConfirmed) {
    const existingInvoice = await this.invoices.findByOrderId(event.orderId);
    if (existingInvoice) {
      logger.info({ event: 'duplicate_event_ignored', eventType: 'OrderConfirmed', orderId: event.orderId.value });
      return; // ya procesado, no es un error
    }
    await this.invoiceGenerator.generate(event);
  }
}
```

Cada consumidor debe diseñar su lógica de modo que repetir el evento sea inocuo (idempotency key natural derivada del evento, ej. `orderId`).

### 5 · Compactación / archivado

Eventos con `published_at IS NOT NULL` se mueven a `outbox.events_archive` semanalmente. La tabla principal se mantiene pequeña (< 100K filas) para que los queries del relay sean rápidos.

Retención del archivo: **18 meses** (suficiente para auditoría operativa; los eventos legales relevantes ya viven en sus aggregates).

## Consecuencias

### Positivas

- **Atomicidad del aggregate + evento** — imposible publicar sin commit ni commitear sin publicar.
- **At-least-once delivery garantizado** — el evento eventualmente sale o queda visible para inspección manual.
- **Auditoría inherente** — la tabla outbox es un log persistente de qué se envió y cuándo. Útil para debugging.
- **Sin dependencia de un broker externo** para garantías — todo dentro de la misma BD que ya tenemos (ADR-004).
- **Resiliencia ante crashes del proceso** — al reiniciar, el relay procesa los eventos pendientes.
- **Compatible con extracción futura a microservicios** — basta cambiar el `eventBus.publish` por una llamada a una cola externa.

### Negativas

- **At-least-once, no exactly-once** — los consumidores deben implementar idempotencia. Es un coste cognitivo permanente.
- **Latencia adicional** — un evento que en in-memory bus se entregaría en microsegundos, vía outbox tarda hasta 500ms (por el polling del relay). Aceptable porque los flujos por evento ya son asíncronos.
- **Una tabla más en el camino crítico de la BD** — escribir en outbox añade una INSERT por evento. Coste despreciable comparado con la transacción del aggregate.
- **Polling consume recursos** — el relay despierta cada 500ms aun sin eventos. Mitigación: si la BD no tiene eventos pendientes, el query es trivial (índice parcial).
- **Compactación necesaria** — sin archivado, la tabla crece indefinidamente.
- **Order de entrega NO garantizado entre eventos de distintos aggregates** — solo se garantiza el orden total dentro de un mismo aggregate (por `occurred_at`).

## Alternativas descartadas

### A · Publicar al bus tras commit (sin outbox)

**Por qué se descartó:**
- Si el publish falla tras el commit, el evento se pierde silenciosamente. Para los flujos legales (factura) es inaceptable.

### B · Publicar antes del commit

**Por qué se descartó:**
- Si el commit falla tras el publish, el evento sale referenciando un aggregate que "no existe" — los suscriptores se confunden o crashean.

### C · Two-phase commit (XA) entre PostgreSQL y un broker

**Por qué se descartó:**
- Complejidad operativa muy alta.
- Pocos brokers soportan XA con confiabilidad.
- Performance pobre comparado con outbox.
- Outbox es el "consenso de la industria" para este problema.

### D · Change Data Capture (CDC) sobre el aggregate

**Por qué se descartó:**
- CDC publica cambios en filas, no eventos de dominio. La traducción de "fila modificada" a "evento de dominio significativo" es no trivial y se vuelve frágil.
- Acopla la forma de los eventos a la forma de las tablas — rompe la idea de Domain Events ricos en información.
- Requiere debezium o similar — más infraestructura.

### E · Event sourcing (la BD es un log de eventos)

**Por qué se descartó:**
- Cambia radicalmente el modelo de persistencia. Equipo no familiarizado.
- Problemas de evolución de schema bien conocidos.
- Beneficios reales solo en sistemas con auditoría extrema (banca, healthcare). El OMS no lo justifica.
- Escala arquitectónica en futuro: dejarse esa puerta abierta sin sufrir su coste hoy.

### F · Cola externa (RabbitMQ) con publicación post-commit

**Por qué se descartó:**
- Sigue teniendo el problema del paso 1 (publish puede fallar tras commit).
- Combinarlo con outbox sería justamente lo que estamos haciendo, pero con un broker más en medio. Innecesario para in-process.

## Re-evaluación

Esta decisión se debe revisar cuando:

- Se **extraiga el primer módulo a servicio independiente** — el relay puede convertirse en un bridge a cola externa (RabbitMQ/Kafka) preservando el patrón.
- El **volumen de eventos** supere ~10K/seg sostenido — el polling deja de ser eficiente; cambiar a notificaciones (LISTEN/NOTIFY de PostgreSQL).
- Aparezca un **caso de uso que requiera ordering global estricto** — replantear (event store + sequence number).

## Referencias

- ADR previos: [ADR-001](ADR-001-monolito-modular.md), [ADR-003](ADR-003-comunicacion-entre-modulos.md), [ADR-004](ADR-004-postgresql-multi-az.md)
- Patrón canónico: Chris Richardson, "Microservices Patterns", Outbox Pattern.

---

> 💡 **NOTA PEDAGÓGICA — Vídeos 6 y 7**
>
> Este ADR es donde la **teoría DDD del Vídeo 6** (eventos de dominio) se convierte en **operación real**. Sin patrón outbox o equivalente, los Domain Events son una promesa débil — funcionan a veces y se pierden cuando hay un crash.
>
> Tres lecciones para alumnos:
>
> 1. **At-least-once vs. exactly-once** — el sistema garantiza que el evento llega al menos una vez. La idempotencia es responsabilidad del consumidor. Esto NO es opcional; entender este modelo es clave para implementar event-driven correctamente.
>
> 2. **El outbox es deuda visible** — eventos con `published_at IS NULL AND attempts >= 10` son problemas reales que requieren acción humana. Documentar este caso operativo (alerta a SRE, runbook) forma parte del entregable.
>
> 3. **El patrón se mantiene cuando extraes a microservicios** — el día que separes el módulo de Orders, el relay deja de publicar en el bus interno y empieza a publicar en una cola externa. El módulo de Orders no se entera.
