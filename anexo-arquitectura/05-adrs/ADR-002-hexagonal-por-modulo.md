# ADR-002 · Arquitectura hexagonal (Ports & Adapters) por módulo

## Estado
**Aceptada** · 2025-01-15

## Contexto

Tras decidir [monolito modular](ADR-001-monolito-modular.md), queda definir el **patrón arquitectónico interno de cada módulo**. El equipo necesita una organización consistente y predecible que cumpla:

- **NFR-MAINT-001** — onboarding ≤ 2 semanas (la estructura debe ser obvia)
- **NFR-MAINT-002** — cobertura de tests del dominio ≥ 85% (necesitamos dominio fácilmente testeable)
- **A-001 / A-002** — proyecto de larga vida (3+ años), proveedores externos pueden cambiar (Stripe → Adyen, PostgreSQL → MongoDB en algunos módulos)
- **NFR-PERF-002** — latencia de creación de pedido < 400ms (la indirección hexagonal es despreciable in-process)
- Posibilidad futura de extraer módulos a servicios separados sin reescribir el dominio

Adicionalmente, los bounded contexts identificados tienen lógica de negocio significativa (no son CRUDs triviales) — especialmente Orders, Inventory y Billing.

> 💡 **NOTA · V5 — Cuándo hexagonal sí**
> Las cinco condiciones del Vídeo 5 para que hexagonal aporte valor:
>
> 1. *Lógica de negocio significativa* → ✓ (orders, inventory, billing)
> 2. *Múltiples canales de entrada* → ✓ (HTTP + eventos + futuro CLI admin)
> 3. *Sistema de larga vida* → ✓ (3+ años)
> 4. *Cambio de proveedores externos* → probable (Stripe, BD)
> 5. *Testabilidad alta del dominio* → ✓ (NFR-MAINT-002)
>
> Las cinco respuestas son sí. Hexagonal es la elección correcta.

## Decisión

Cada módulo del monolito sigue **arquitectura hexagonal (Ports & Adapters)** con la siguiente estructura:

```
src/modules/<bounded-context>/
├── domain/
│   ├── entities/         (Order.ts, OrderItem.ts, ...)
│   ├── value-objects/    (Money.ts, OrderId.ts, ...)
│   ├── usecases/         (CreateOrderUseCase.ts, CancelOrderUseCase.ts)
│   └── ports/
│       ├── driving/      (interfaces que el dominio expone hacia adapters de entrada)
│       └── driven/       (interfaces que el dominio necesita de adapters de salida)
├── adapters/
│   ├── http/             (controllers REST)
│   ├── queue/            (consumidores de eventos)
│   ├── persistence/      (impl. de repositorios contra PostgreSQL)
│   └── (otros driven)    (Redis cache, Stripe gateway, etc.)
└── module.ts             (composition: instancia adapters + use cases)
```

**Reglas inviolables del módulo:**

1. **El dominio no importa NADA externo.** Ningún paquete de Express, pg, Stripe, Spring, Hibernate, etc. dentro de `domain/`.
2. **Los puertos viven en el dominio.** Las interfaces (`OrderRepository`, `PaymentGateway`, `Notifier`) están en `domain/ports/driven/` o `domain/ports/driving/`.
3. **Los adapters viven fuera del dominio** y los implementan.
4. **El composition root** (`module.ts` o `main.ts`) es el ÚNICO sitio donde se conectan adapters concretos a use cases del dominio.
5. **Tests de dominio sin BD ni red.** El dominio se testea con doubles in-memory de los puertos.
6. **Tests de arquitectura en CI.** dependency-cruiser (Node) o ArchUnit (Java) bloquean cualquier import del dominio hacia fuera.

## Consecuencias

### Positivas

- **Tests de dominio rapidísimos** (< 1 segundo) — facilita NFR-MAINT-002.
- **El dominio es portable** — si mañana migramos del monolito a un microservicio, el código del dominio no cambia.
- **Cambio de proveedores externos barato** — sustituir Stripe por Adyen es escribir un nuevo `AdyenPaymentGateway`; el dominio no se entera.
- **Múltiples canales de entrada sin duplicar lógica** — añadir un consumidor de cola que reuse `CreateOrderUseCase` son ~30 líneas de código.
- **Onboarding consistente** — un developer que aprende un módulo (p. ej. catalog) sabe leer todos los demás.
- **El lenguaje del dominio aparece en el código** — la clase se llama `Order.confirm()`, no `OrderEntity.update(status="CONFIRMED")`. Es la base para que DDD aporte valor (V6).

### Negativas

- **Más boilerplate inicial** que un controlador "directo a la BD". Para el primer endpoint trivial son ~3-4 archivos en lugar de uno. Mitigación: plantilla + scaffolding generator. Pago: a partir del 5º endpoint del módulo, hexagonal es más barato que el patrón directo.
- **Indirección extra** al razonar sobre flujos cross-módulo. Mitigación: tracing distribuido (NFR-MAINT-003) hace los flujos visibles en runtime.
- **Riesgo de sobre-abstracción** (interfaces para cosas que solo tienen una implementación trivial). Mitigación: regla "interfaz solo cuando hay > 1 implementación o cruce de capa". Sin esa regla, el dominio se llena de ruido.
- **Curva de aprendizaje inicial** para developers junior que vienen de patrones ActiveRecord o anémicos. Mitigación: pair programming en las primeras semanas, plantilla del primer módulo como referencia.

## Alternativas descartadas

### A · Capas tradicionales (Controller → Service → Repository)

**Por qué se descartó:**
- En la práctica, el "Service" suele acabar como un saco de funciones sin modelo de dominio rico (modelo anémico — antipatrón explícito en V4).
- Las dependencias suelen apuntar de Controller hacia Service hacia Repository, donde Repository conoce un ORM concreto. Esto acopla el "dominio" (en realidad, los Services) al ORM.
- Multi-canal de entrada es duplicación: cada Controller debe replicar la lógica.
- Es válido para CRUDs pequeños, no para el OMS donde Orders tiene reglas de negocio significativas.

### B · Hexagonal estricto solo para Orders, capas tradicionales para el resto

**Por qué se descartó:**
- Inconsistencia en la base de código → onboarding más lento (incumple NFR-MAINT-001).
- "Catalog es solo lectura, no necesita hexagonal" suena razonable hoy pero pasado un año aparecen reglas de negocio (descuentos por volumen, disponibilidad regional, etc.) y refactorizar a hexagonal es más caro que haberlo hecho desde el inicio.
- La regla de oro del módulo: la consistencia arquitectónica entre módulos vale más que la "optimización" puntual.

### C · Hexagonal "ligero" (puertos pero sin separación driving/driven)

**Por qué se descartó:**
- La separación driving/driven es exactamente lo que hace que hexagonal sea fácil de extender. Sin ella, los developers acaban poniendo HTTP controllers en el mismo paquete que repositorios → confusión.
- El coste de tener dos subcarpetas en `ports/` es nulo.

### D · Onion Architecture / Clean Architecture estricta (4 capas)

**Por qué se descartó:**
- Esencialmente equivalente a hexagonal en este contexto. La diferencia es vocabulario y carpeteo.
- El equipo actual está más familiarizado con "puertos y adapters" que con "use cases / interface adapters / frameworks". Decisión por familiaridad (criterio del V2: cuando hay opciones equivalentes, gana la más familiar).

## Re-evaluación

Esta decisión se debe revisar cuando:

- Aparezca **un módulo que sea CRUD trivial sin lógica de negocio** durante > 6 meses. En ese caso, evaluar si simplificar a capas tradicionales para ese módulo concreto.
- La **boilerplate** de los puertos para casos de uso simples se vuelva un cuello de botella de productividad mensurable. Mitigación previa: scaffolding tool.
- Aparezcan **patrones más adecuados** (CQRS estricto, event sourcing) que un dominio o varios necesiten.

## Referencias

- ADR previo: [ADR-001 · Monolito modular](ADR-001-monolito-modular.md)
- Bounded contexts: [02-bounded-contexts.md](../02-bounded-contexts.md)
- ADR siguiente: [ADR-003 · Comunicación entre módulos](ADR-003-comunicacion-entre-modulos.md)

---

> 💡 **NOTA PEDAGÓGICA — Vídeos 4 y 5**
>
> El Vídeo 4 establece la regla (Dependency Rule): las dependencias apuntan hacia adentro. El Vídeo 5 da el vocabulario operativo (puertos y adapters). Este ADR aplica ambos.
>
> Si lees `domain/ports/driven/PaymentGateway.ts` y entiendes que el dominio define lo que necesita y otra capa lo implementa — has internalizado el módulo. Si te pierdes, vuelve al V4 (sección 3 sobre independencia de frameworks) y al V5 (sección 1 sobre la metáfora del hexágono).
>
> El test mental que repetimos en clase: **"si quitas el framework y la lógica de negocio deja de compilar, has acoplado el dominio."** Aquí la disciplina la fuerzan los tests de arquitectura en CI.
