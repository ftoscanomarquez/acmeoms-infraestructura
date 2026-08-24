> ℹ️ **Material de referencia (anexo).** Generado desde `miseia/m2-2-arquitectura-derivada-de-la-especificacion` · no editar aquí.

# Proyecto integrador — OMS · Arquitectura derivada

> **Vídeo 10 del módulo de Arquitectura derivada**
> Aplicar todo lo aprendido: leer la spec, extraer restricciones, derivar decisiones, documentarlas.

Este es el conjunto completo de entregables que un alumno debería producir como ejercicio integrador del módulo. El sistema modelado es el **OMS — Order Management System** especificado en el módulo anterior (Requisitos y Especificación).

---

## Cómo está organizado

```
anexo-arquitectura/
├── README.md                          ← (este archivo)
├── 01-inventario-restricciones.md     ← entregable 1
├── 02-bounded-contexts.md             ← entregable 2
├── 03-arquitectura.md                 ← entregable 3
├── 04-revision-cruzada.md             ← entregable 4
└── 05-adrs/
    ├── ADR-001-monolito-modular.md
    ├── ADR-002-hexagonal-por-modulo.md
    ├── ADR-003-comunicacion-entre-modulos.md
    ├── ADR-004-postgresql-multi-az.md
    ├── ADR-005-redis-cache-catalogo.md
    ├── ADR-006-stripe-tokenizacion.md
    ├── ADR-007-regiones-despliegue.md
    ├── ADR-008-frontend-spa-cdn.md
    ├── ADR-009-outbox-pattern.md
    └── ADR-010-audit-trail-gdpr.md
```

---

## Los cuatro entregables

| # | Entregable | Pregunta que responde | Vídeo del módulo |
|---|------------|----------------------|------------------|
| 1 | Inventario de restricciones | ¿Qué condiciona la arquitectura? | V1, V2 |
| 2 | Mapa de bounded contexts | ¿Cómo descomponemos el dominio? | V6 |
| 3 | Documento de arquitectura | ¿Qué construimos y cómo se relaciona? | V3, V4, V5, V7 |
| 4 | ADRs (uno por decisión clave) | ¿Por qué elegimos esto y no aquello? | V1, V2, V10 |

---

## Cómo leer este proyecto

Los artefactos están pensados para leerse en orden:

1. **Inventario** primero — es el input del proceso de derivación.
2. **Bounded contexts** — descomposición del dominio en zonas coherentes.
3. **Arquitectura** — el resultado de aplicar las decisiones a los inputs.
4. **ADRs** — la justificación detallada de cada decisión clave.
5. **Revisión cruzada** — checklist que valida la coherencia del conjunto.

Cada artefacto incluye **comentarios pedagógicos** marcados con `> 💡 NOTA` que conectan la decisión concreta con conceptos vistos en los vídeos del módulo. Los alumnos pueden usarlos como mapa de retorno a las clases.

---

## Alcance del sistema OMS (recordatorio)

- E-commerce B2C con catálogo navegable, carrito, checkout, pagos, gestión de pedidos y facturación
- 50.000 usuarios activos, ~2.000 pedidos/día en operación normal
- Pico Black Friday: ~10.000 pedidos/día (5×)
- Operación: España (cliente final), backoffice en oficinas en Madrid y Barcelona
- Cumplimiento: GDPR (datos en UE), PCI-DSS (pagos con tarjeta), normativa fiscal española

---

## Cómo se hizo este proyecto en clase

El alumno trabaja sobre el OMS especificado en el módulo M1 y produce los cuatro entregables siguiendo el proceso de cinco pasos del Vídeo 2:

1. **Inventariar** restricciones → entregable 01
2. **Clasificar** por tipo → entregable 01 (sección final)
3. **Identificar** decisiones candidatas → entregable 03
4. **Evaluar** conflictos y trade-offs → ADRs (sección "Alternativas")
5. **Documentar** decisiones → ADRs

Lo que ves en este repositorio es el resultado completo. Sirve como referencia, no como solución única — vuestra spec puede tener restricciones distintas y derivar otras decisiones.

---

## Convenciones

- **IDs trazables** — cada restricción tiene un ID (NFR-PERF-001, OPS-001, REG-GDPR-001, etc.) que se cita explícitamente en cada decisión que la cumple.
- **Inmutabilidad de los ADRs** — una vez aceptados no se modifican; si una decisión cambia se crea un ADR superseder.
- **Honestidad en consecuencias** — cada ADR documenta consecuencias positivas Y negativas.
- **Alternativas descartadas con razón** — no vale "consideramos X y lo descartamos"; hay que decir por qué.

---

## Mapa de retorno a los vídeos

Si al leer estos artefactos hay algo que no entiendes, este es el orden de retorno a las clases:

| Tema | Volver al vídeo |
|------|-----------------|
| ¿Por qué la arquitectura se deriva, no se inventa? | V1 |
| ¿Cómo se hace el proceso de derivación paso a paso? | V2 |
| ¿Por qué empezamos con monolito modular? | V3 |
| ¿Por qué el dominio no depende de Spring/Express? | V4 |
| ¿Qué son ports y adapters? ¿Por qué los usamos? | V5 |
| ¿Qué son bounded contexts, aggregates, eventos? | V6 |
| ¿Cómo se controlan las dependencias entre módulos? | V7 |
| ¿Cómo se ve esto en Node.js / Express? | V8 |
| ¿Cómo se ve esto en Java / Spring Boot? | V9 |
| Volver a este proyecto desde cero | V10 |

Buen viaje.
