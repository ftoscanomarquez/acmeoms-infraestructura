# 04 · Revisión cruzada del documento de arquitectura

> **Entregable 4 de 4** — Aplicación del Vídeo 10, sección 5.
>
> **Objetivo:** validar la coherencia del conjunto de entregables. Cada decisión debe tener una restricción que la justifique, y cada restricción debe tener una decisión que la cumpla.

> 💡 **NOTA · V10 — Por qué la revisión cruzada importa**
> Un equipo de 1 persona puede engañarse a sí mismo. Un equipo de 2 personas puede engañarse colectivamente. La revisión cruzada — el proceso por el cual alguien que NO tomó la decisión la cuestiona — es el único antídoto fiable. Documenta esta revisión: forma parte del producto, no es opcional.

---

## Cómo se hizo esta revisión

**Revisores:**
- **Tech Lead** del proyecto (autor del documento).
- **SRE Senior** del equipo de operaciones (no autor).
- **Product Owner** (negocio).
- **Compliance Officer externo** (DPO subcontratado para revisión GDPR/PCI).

**Fecha:** 2025-01-22 (1 semana después de aceptar los ADRs en draft).

**Método:**
1. Cada revisor leyó los entregables sin contexto adicional del autor durante 2 horas.
2. Sesión conjunta de 90 minutos para revisar checklist y discutir hallazgos.
3. Acciones de mejora documentadas y asignadas.

---

## Paso 1 · Revisor lee solo el documento

> **Pregunta:** ¿el documento se entiende sin que el autor lo explique?

| Revisor | Veredicto | Observaciones |
|---------|-----------|---------------|
| SRE | ✓ Comprensible | Pidió clarificación en runbook de DR (ADR-007) — añadido al documento. |
| PO | ✓ Comprensible (parcialmente) | Los ADRs son densos para no técnicos. Sugerencia aceptada: añadir resumen ejecutivo en `03-arquitectura.md` sección 1. |
| Compliance | ✓ Comprensible | Solicitó que las restricciones GDPR/PCI estén numeradas y trazadas explícitamente. Hecho. |

**Conclusión:** documento aprobado para entendimiento. Comprensible para audiencia técnica + auditor; PO puede leer secciones ejecutivas.

---

## Paso 2 · Revisor cuestiona cada ADR

> **Pregunta:** ¿están todas las decisiones justificadas con contexto, alternativas concretas y consecuencias honestas?

### Checklist por ADR

| ADR | Contexto cita NFRs/OPS/REG concretos | Decisión accionable y específica | Consecuencias positivas Y negativas | Alternativas con razón concreta | Re-evaluación con triggers |
|-----|:-:|:-:|:-:|:-:|:-:|
| ADR-001 Monolito modular | ✓ | ✓ | ✓ (4+/4-) | ✓ (4 alternativas) | ✓ |
| ADR-002 Hexagonal por módulo | ✓ | ✓ | ✓ (6+/4-) | ✓ (4 alternativas) | ✓ |
| ADR-003 Comunicación | ✓ | ✓ | ✓ (5+/4-) | ✓ (5 alternativas) | ✓ |
| ADR-004 PostgreSQL | ✓ | ✓ | ✓ (8+/6-) | ✓ (6 alternativas) | ✓ |
| ADR-005 Redis caché | ✓ | ✓ | ✓ (6+/5-) | ✓ (5 alternativas) | ✓ |
| ADR-006 Stripe | ✓ | ✓ | ✓ (6+/6-) | ✓ (5 alternativas) | ✓ |
| ADR-007 Regiones | ✓ | ✓ | ✓ (5+/5-) | ✓ (5 alternativas) | ✓ |
| ADR-008 Frontend SPA | ✓ | ✓ | ✓ (7+/5-) | ✓ (5 alternativas) | ✓ |
| ADR-009 Outbox | ✓ | ✓ | ✓ (6+/6-) | ✓ (6 alternativas) | ✓ |
| ADR-010 Audit GDPR | ✓ | ✓ | ✓ (6+/5-) | ✓ (5 alternativas) | ✓ |

**Conclusión:** los 10 ADRs cumplen el formato canónico. Sin ADRs marketing.

### Hallazgos cualitativos

- **ADR-002:** Compliance pidió añadir test de arquitectura específico que detecte imports de Stripe en el dominio. Aceptado, pendiente de implementación en sprint 1.
- **ADR-005:** SRE preguntó por estrategia ante "thundering herd" al expirar TTL en clave caliente. ADR ya menciona single-flight, pero se añade ejemplo concreto en el documento.
- **ADR-009:** PO preguntó qué pasa con eventos que llevan meses sin publicar. Respuesta: alerta automática a SRE cuando attempts >= 10 (ya en ADR). Confirmado.

---

## Paso 3 · Mapeo restricción → decisión

> **Pregunta:** ¿cada restricción del inventario tiene al menos una decisión documentada que la cumple?

| Categoría | Total restricciones | Cubiertas | Sin decisión |
|-----------|---------------------|-----------|--------------|
| Rendimiento | 4 | 4 | 0 |
| Escalabilidad | 2 | 2 | 0 |
| Disponibilidad | 3 | 3 | 0 |
| Seguridad | 4 | 4 | 0 |
| Mantenibilidad | 4 | 4 | 0 |
| Operativas | 7 | 7 | 0 |
| Regulatorias | 9 | 9 | 0 |
| Funcionales con impacto | 5 | 5 | 0 |
| **Total** | **38** | **38** | **0** |

> Nota: las 5 asunciones (A-001..005) no son restricciones que cumplir, son condiciones de validez. No se cuentan aquí.

**Conclusión:** cobertura 100%. Cada restricción tiene una decisión que la implementa, documentada en el ADR correspondiente o en `03-arquitectura.md` (decisiones derivadas de ADRs).

### Trazabilidad inversa: decisión → restricción

| Decisión | Restricciones que justifica |
|----------|------------------------------|
| ADR-001 Monolito modular | OPS-001, OPS-002, OPS-003, NFR-SCAL-001, NFR-MAINT-001, FR-001 |
| ADR-002 Hexagonal por módulo | NFR-MAINT-001, NFR-MAINT-002, NFR-PERF-002 |
| ADR-003 Comunicación | NFR-PERF-002, FR-001, FR-014, FR-022 |
| ADR-004 PostgreSQL multi-AZ | NFR-AVAIL-001, NFR-AVAIL-002, OPS-005, OPS-003, NFR-SEC-001, FR-001 |
| ADR-005 Redis caché | NFR-PERF-001, NFR-AVAIL-002 |
| ADR-006 Stripe | REG-PCI-001, REG-PCI-002, NFR-SEC-003, NFR-SEC-002 |
| ADR-007 Regiones | REG-GDPR-001, NFR-AVAIL-001, OPS-005 |
| ADR-008 Frontend SPA + CDN | NFR-PERF-001 (UI), NFR-AVAIL-002, NFR-SEC-002, OPS-003 |
| ADR-009 Outbox | FR-001, FR-014, FR-022, REG-GDPR-002 (entrega fiable) |
| ADR-010 Audit GDPR | REG-GDPR-002, REG-GDPR-003, REG-GDPR-004, FR-038 |

**Conclusión:** ningún ADR es huérfano (sin restricción que lo justifique).

---

## Paso 4 · Búsqueda de contradicciones

> **Pregunta:** ¿hay decisiones que se anulan entre sí o que entran en conflicto sin resolverlo?

### Contradicciones potenciales analizadas

#### A · "Multi-AZ activo-pasivo" (ADR-004) vs. "99.9% uptime" (NFR-AVAIL-001)

¿Es 99.9% alcanzable con activo-pasivo? Sí — el failover típico es < 60 segundos. En el peor caso del año (un failover anual de 3 minutos), el downtime es muy inferior a los 43 min/mes que tolera el SLA. **No hay contradicción.**

#### B · "Despliegues solo 09:00–18:00" (OPS-002) vs. "99.9% uptime" (NFR-AVAIL-001)

¿Es 99.9% compatible con la ventana de despliegue restringida? Sí, si los despliegues son zero-downtime (rolling con health checks, ADR-001). Si un despliegue requiere downtime, debe pedirse ventana de mantenimiento programado, que NFR-AVAIL-003 permite fuera de horario comercial. **No hay contradicción**, pero se añade clarificación: los despliegues que requieran downtime van fuera del horario comercial bajo NFR-AVAIL-003 explícitamente.

#### C · "Caché de catálogo" (ADR-005) vs. "Derecho al olvido GDPR" (REG-GDPR-002)

¿Qué pasa si un usuario solicita borrado y su userId aparece en una clave cacheada? El catálogo NO contiene PII de usuarios — solo productos. Las claves de caché son `product:{id}` y `listings:{cat}:{page}`. **No hay contradicción.**

(Si en el futuro se cachearan datos personalizados por usuario — recomendaciones, p. ej. — habría que añadir invalidación de caché en el workflow de borrado.)

#### D · "Anonimización en lugar de borrado físico de pedidos" (ADR-010) vs. "Derecho al olvido" (REG-GDPR-002)

¿La anonimización satisface GDPR? Sí, según la guía del EDPB: la anonimización con datos no reversibles es equivalente al borrado a efectos GDPR, siempre que se conserven los datos por una obligación legal vigente (REG-IVA-002). **No hay contradicción** y el reasoning está documentado en ADR-010.

#### E · "Outbox en la misma BD" (ADR-009) vs. "Acoplamiento físico" (debilidad de ADR-004)

Si la BD cae, el outbox no funciona. ¿Es un problema? Si la BD cae, todo el sistema cae igualmente — la transacción del aggregate ni siquiera se completa. El outbox no introduce un punto de fallo nuevo. **No hay contradicción.**

#### F · "TLS 1.3" (NFR-SEC-002) vs. "TLS 1.2 fallback" (ADR-008)

¿Es aceptable TLS 1.2 si el NFR pide 1.3? El NFR dice "1.3 (TLS 1.2 mínimo aceptable)" — el fallback se permite explícitamente. **No hay contradicción.**

**Conclusión:** las potenciales contradicciones son aparentes; cada una se resuelve con un detalle ya documentado o con un matiz que se añade al texto.

---

## Paso 5 · Checklist final consolidado

### Revisión técnica

- [x] Cada decisión tiene un ADR
- [x] Cada ADR cita restricciones específicas (con IDs)
- [x] Cada ADR tiene alternativas descartadas con razón concreta
- [x] No hay ciclos en las dependencias entre módulos (verificado en context map y ADR-003)
- [x] Los puertos viven en `domain/`, los adapters fuera (ADR-002 + tests de arquitectura en CI)
- [x] El composition root está identificado (cada módulo + main)
- [x] Tests de dominio rápidos (sin BD, sin red) — verificable por NFR-MAINT-002
- [x] La estructura de carpetas refleja la arquitectura (sección 4 de `03-arquitectura.md`)

### Revisión de spec

- [x] Todas las restricciones del SRS están cubiertas (38/38)
- [x] No hay decisiones sin restricción que las justifique
- [x] NFRs cuantificados se traducen a métricas observables (definidas en ADRs y sección 7.2 de `03-arquitectura.md`)
- [x] Restricciones regulatorias tienen mecanismo de cumplimiento explícito
- [x] RPO/RTO se traducen a estrategia de backup/DR (ADR-004 + ADR-007)
- [x] Asunciones documentadas y trazadas a decisiones que dependen de ellas

### Revisión de cumplimiento (Compliance Officer)

- [x] GDPR — Art. 32 (Integrity and confidentiality) cubierto por NFR-SEC-001/002, ADR-010
- [x] GDPR — Art. 17 (Right to erasure) cubierto por ADR-010 con plazo interno 15 días
- [x] GDPR — Art. 20 (Right to data portability) cubierto por FR-038, ADR-010
- [x] GDPR — Art. 30 (Records of processing) cubierto por audit log
- [x] PCI-DSS — alcance reducido a SAQ-A vía ADR-006
- [x] LSSI / RGPD-LOPD — política de cookies y consent versionado documentado en ADR-010
- [x] Ley 37/1992 (IVA español) — módulo billing con correlativo y retención (REG-IVA-001/002)

### Revisión operativa (SRE)

- [x] Runbooks documentados:
  - `infra/runbooks/regional-failover.md` (ADR-007)
  - `infra/runbooks/restore-from-backup.md` (ADR-004)
  - `infra/runbooks/gdpr-deletion.md` (ADR-010)
  - `infra/runbooks/incident-response.md` (REG-GDPR-005)
- [x] Alertas configuradas para:
  - Eventos en outbox con attempts >= 10 (ADR-009)
  - Solicitudes de borrado pendientes > 20 días (ADR-010)
  - Latencia p95 fuera de NFR
  - Failover de PostgreSQL
  - Hit ratio Redis < 70%
- [x] Backups verificados en ejercicio mensual
- [x] Rotación de credenciales/secretos automática (Secrets Manager)

---

## Resumen de cambios derivados de la revisión

| # | Cambio | Origen | Estado |
|---|--------|--------|--------|
| 1 | Añadir resumen ejecutivo en sección 1 de `03-arquitectura.md` | PO | ✅ Aplicado |
| 2 | Numerar y trazar restricciones GDPR explícitamente | Compliance | ✅ Aplicado |
| 3 | Clarificar runbook de regional failover | SRE | ✅ Aplicado |
| 4 | Añadir test de arquitectura que detecte imports de Stripe en domain/ | Compliance | 🔧 Backlog sprint 1 |
| 5 | Añadir ejemplo concreto de single-flight para Redis stampede | SRE | ✅ Aplicado |
| 6 | Clarificar que despliegues con downtime van bajo NFR-AVAIL-003 | SRE | ✅ Aplicado |
| 7 | Añadir nota sobre invalidación de caché si se cachean datos personalizados | Compliance | ✅ Aplicado en ADR-005 |

---

## Aprobación

| Revisor | Rol | Decisión | Fecha |
|---------|-----|----------|-------|
| [Tech Lead] | Autor | Aprueba | 2025-01-22 |
| [SRE Senior] | Operaciones | Aprueba con cambios menores ✅ | 2025-01-22 |
| [Product Owner] | Negocio | Aprueba | 2025-01-22 |
| [DPO externo] | Compliance | Aprueba | 2025-01-23 |

**Decisión:** los 4 entregables se consideran completos y consistentes. La arquitectura está derivada y justificada. El proyecto puede pasar al módulo siguiente (Implementación de calidad).

---

## Próximos pasos

Esta revisión cruzada **no es el final** sino una validación de que el documento está listo para ser ejecutado. A partir de aquí:

1. **Sprint 1** — implementación del esqueleto del monolito (estructura de carpetas, composition root, primer caso de uso end-to-end con tests).
2. **Sprint 2-3** — módulos `iam` y `catalog` completos.
3. **Sprint 4-6** — módulos `inventory`, `orders`, `payments`.
4. **Sprint 7-8** — módulo `billing` y workflow GDPR.
5. **Sprint 9** — hardening, observabilidad completa, ejercicio de DR.

Cada sprint puede generar nuevos ADRs (decisiones que solo aparecen al implementar) o ADRs superseder (cuando se descubre que una decisión inicial necesita revisarse). El documento de arquitectura se mantiene vivo.

---

> 💡 **NOTA FINAL · V10 — La arquitectura está hecha**
>
> Si has leído los cuatro entregables y entiendes cómo cada decisión deriva de las restricciones, y cómo se relacionan entre sí, has completado el trabajo del módulo de Arquitectura derivada.
>
> La arquitectura justificada es lo que distingue a un equipo profesional de uno que improvisa. Los ADRs no son burocracia — son **memoria de equipo**: dentro de un año, alguien hará una pregunta cuya respuesta vive en uno de estos documentos. Sin ellos, el equipo redescubre las decisiones cada vez (y a menudo las cambia mal).
>
> El siguiente paso del máster es construir esto. Pero la arquitectura que vais a implementar es esta. Las decisiones ya están tomadas, justificadas y revisadas.
