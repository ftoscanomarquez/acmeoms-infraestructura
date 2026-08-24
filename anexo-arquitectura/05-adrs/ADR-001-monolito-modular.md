# ADR-001 · Monolito modular como granularidad inicial

## Estado
**Aceptada** · 2025-01-15

## Contexto

El sistema OMS debe servir un e-commerce B2C con catálogo, pedidos, pagos y facturación en España. Las restricciones del [inventario](../01-inventario-restricciones.md) que afectan a esta decisión son:

- **OPS-001** — equipo de 8 developers + 2 SREs (capacidad operativa limitada)
- **OPS-003** — presupuesto infraestructura: 800 €/mes (no soporta plataforma de microservicios)
- **NFR-SCAL-001** — pico Black Friday 5× (alcanzable con autoscaling de un monolito stateless)
- **NFR-MAINT-001** — onboarding de developer en ≤ 2 semanas
- **OPS-002** — despliegues solo en horario de oficina (descarta zero-downtime cross-service complejo)

Adicionalmente, el producto está en fase de crecimiento con cambios frecuentes. Los bounded contexts ya están identificados (ver [02-bounded-contexts](../02-bounded-contexts.md)) pero el equipo es lo bastante pequeño como para que separarlos en servicios independientes sea contraproducente hoy.

> 💡 **NOTA · V3 — Las cinco preguntas de granularidad**
>
> 1. *¿Cuántos devs en los próximos 2 años?* → ≤ 14, dentro de la zona donde monolito es óptimo.
> 2. *¿Hay módulos con cargas muy distintas?* → Catálogo es 2-3× más caliente, no 10×. No justifica separar.
> 3. *¿Restricciones de release diferenciadas?* → No. SLA uniforme 99.9%.
> 4. *¿Plataforma operativa madura?* → No. Dos SREs sin observabilidad distribuida ni service mesh.
> 5. *¿SLA exigido uniforme?* → Sí.
>
> **Las cinco respuestas apuntan a monolito modular.**

## Decisión

Implementar el OMS como **monolito modular** con **6 módulos** correspondientes a los bounded contexts identificados:

- `catalog` · `inventory` · `orders` · `payments` · `billing` · `iam`

**Características concretas:**

1. **Una sola base de código** en un único repositorio.
2. **Un único deployable** (contenedor Docker) — un proceso, un puerto HTTP.
3. **Esquemas separados en PostgreSQL** — `catalog.*`, `inventory.*`, `orders.*`, etc. Ningún módulo lee/escribe directamente en tablas de otro.
4. **APIs internas explícitas** entre módulos vía puertos del dominio (ver [ADR-002](ADR-002-hexagonal-por-modulo.md) y [ADR-003](ADR-003-comunicacion-entre-modulos.md)).
5. **Comunicación síncrona o por evento** entre módulos según el caso (ADR-003).
6. **Servicios stateless** para permitir autoescalado horizontal: la sesión vive en JWT (cliente) y el carrito en Redis con TTL.

## Consecuencias

### Positivas

- **Coste operativo bajo** — un servicio para mantener, monitorizar, parchear. Encaja en presupuesto OPS-003.
- **Transacciones ACID disponibles entre módulos** — el flujo de creación de pedido (FR-001) puede ser atómico sin sagas.
- **Onboarding rápido** — un developer aprende el sistema en ~2 semanas (NFR-MAINT-001) porque no hay plataforma compleja por encima.
- **Stack tecnológico unificado** — menos cosas que aprender, menos cosas que mantener.
- **Latencia inter-módulo en microsegundos** (in-process) — facilita cumplir NFR-PERF-002.
- **Tests de integración rápidos** con InMemory adapters; suite e2e completa razonable.
- **Capacidad de autoescalado horizontal** porque el contenedor es stateless — cumple NFR-SCAL-001.

### Negativas

- **Despliegue acoplado** entre módulos — un cambio en `catalog` requiere redeploy de todo el monolito. Mitigación: pipeline rápido, rolling update.
- **Imposible escalar módulos por separado** — si `catalog` necesita más CPU, escalamos el binario entero. Coste real: aceptable mientras el ratio CPU/memoria por módulo no diverja mucho.
- **Migración futura a microservicios será trabajo no trivial** — pero los puertos hexagonales ya existirán, lo que reduce el coste de extracción. Mitigación: no extraer nada hasta que una restricción concreta lo justifique.
- **Riesgo de erosión arquitectónica** (acoplamiento creciente entre módulos) si la disciplina decae. Mitigación: tests de arquitectura automáticos en CI (dependency-cruiser / ArchUnit).

## Alternativas descartadas

### A · Microservicios desde el inicio (uno por bounded context)

**Por qué se descartó:**
- OPS-001 (equipo de 10 personas) — la complejidad operativa de microservicios consume entre 30-50% de la capacidad de un equipo pequeño en mantener la plataforma en lugar de entregar valor.
- OPS-003 (presupuesto 800 €/mes) — microservicios típicamente cuestan 3-10× más en infraestructura. Una estimación realista (6 servicios × 2 réplicas mínimas + service mesh + observabilidad distribuida + secret management) sería ~2.500 €/mes, fuera de presupuesto.
- Sin SREs dedicados a la plataforma, los incidentes operativos cascada serían recurrentes.
- El coste de saga distribuida para FR-001 (crear pedido) en microservicios añade ~500 líneas de código y casos de fallo a gestionar (compensaciones, idempotencia, timeouts), comparado con una transacción ACID en monolito.

> 💡 **NOTA · V3 — La curva de coste**
> En la curva equipo vs. coste, microservicios se vuelven competitivos a partir de ~30 developers en el sistema. Por debajo, son entre 3-5× más caros para entregar el mismo valor.

### B · Monolito desordenado (sin módulos delimitados)

**Por qué se descartó:**
- Es el camino directo a deuda arquitectónica acumulada. Acoplamiento por implementación → cualquier cambio rompe en sitios inesperados → onboarding lento (incumple NFR-MAINT-001) → miedo a refactorizar → más deuda.
- No hay ventaja real frente a monolito modular: el coste de mantener la disciplina de módulos es bajo (~5% más esfuerzo en code review) y el retorno es enorme.

### C · Modulith con SQLite embebido por módulo (per-module storage)

**Por qué se descartó:**
- Pierde transacciones ACID entre módulos — habría que orquestar consistencia eventual desde el día 1, contraviniendo el espíritu de FR-001.
- Backup, replicación y multi-AZ se vuelven idiosincráticos por módulo.
- No aporta beneficio real sobre PostgreSQL único con esquemas separados.

### D · Monolito con base de datos compartida sin esquemas

**Por qué se descartó:**
- Cualquier módulo podría leer/escribir en tablas de otro → frontera de bounded context se erosiona en el primer mes.
- Imposibilita extracción futura de un módulo a servicio sin reescribir el acceso a datos.

## Re-evaluación

Esta decisión se debe revisar cuando se cumpla **cualquiera** de las siguientes condiciones:

- El equipo crece a **> 25 personas** en el sistema (zona en que monolito empieza a doler).
- Un módulo concreto necesita **SLA diferenciado** del resto (p. ej., catalog 99.99% mientras el resto vive con 99.9%).
- Un módulo concreto necesita **ciclo de release independiente** por restricción regulatoria que no aplica al resto.
- El **perfil de carga** de un módulo diverge en > 10× del resto, haciendo ineficiente escalar todo junto.

En esos escenarios, el primer candidato a extraer es el módulo concreto que motiva la revisión, no toda la arquitectura. La estrategia "monolith-first" preserva esta opcionalidad.

## Referencias

- Inventario: [01-inventario-restricciones.md](../01-inventario-restricciones.md)
- Bounded contexts: [02-bounded-contexts.md](../02-bounded-contexts.md)
- ADR relacionado: [ADR-002 · Hexagonal por módulo](ADR-002-hexagonal-por-modulo.md)
- ADR relacionado: [ADR-003 · Comunicación entre módulos](ADR-003-comunicacion-entre-modulos.md)
- ADR relacionado: [ADR-004 · PostgreSQL multi-AZ](ADR-004-postgresql-multi-az.md)

---

> 💡 **NOTA PEDAGÓGICA — Vídeo 3**
>
> Este ADR es la aplicación canónica del Vídeo 3 del módulo. Si lo lees y no entiendes por qué la curva de coste favorece al monolito en este caso, vuelve al vídeo y revisa especialmente la sección 4: "Criterios de decisión derivados de la spec".
>
> La frase clave del módulo: **"el monolito modular es el punto de partida sano para casi cualquier proyecto nuevo"**. Aquí la vemos en acción.
