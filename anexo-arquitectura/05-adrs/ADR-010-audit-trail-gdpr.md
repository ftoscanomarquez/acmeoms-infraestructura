# ADR-010 · Audit trail inmutable y workflow de cumplimiento GDPR

## Estado
**Aceptada** · 2025-01-15

## Contexto

GDPR impone obligaciones técnicas concretas que el sistema OMS debe cumplir:

- **REG-GDPR-002** — derecho al olvido: borrar PII en ≤ 30 días tras solicitud
- **REG-GDPR-003** — audit trail inmutable de accesos a datos personales
- **REG-GDPR-004** — consentimiento explícito y versionado para tratamiento
- **REG-GDPR-005** — notificación de breach en ≤ 72h
- **FR-038** — exportar pedidos del usuario en formato CSV (data subject access)

Estas obligaciones se traducen en requisitos técnicos cross-cutting: cualquier acceso a PII debe loggearse, cualquier borrado debe propagarse en cascada por todos los bounded contexts, las exportaciones deben ser reproducibles.

> 💡 **NOTA · V1 — Restricciones inflexibles**
> El incumplimiento de GDPR conlleva multas de hasta 20M€ o 4% del revenue global. Estas restricciones **no se priorizan**: o se cumplen o no se opera.

## Decisión

Implementar **tres componentes** para cumplir las obligaciones GDPR:

### 1 · Audit Log inmutable (REG-GDPR-003)

Tabla `shared.audit_log` en PostgreSQL, **append-only por convención y por permisos**:

```sql
CREATE TABLE shared.audit_log (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    occurred_at     timestamptz NOT NULL DEFAULT now(),
    actor_type      text NOT NULL,         -- 'user', 'admin', 'system', 'api'
    actor_id        text,                  -- userId, adminId, etc.
    action          text NOT NULL,         -- 'access', 'modify', 'delete', 'export', 'consent'
    resource_type   text NOT NULL,         -- 'user_pii', 'order', 'invoice'
    resource_id     text NOT NULL,         -- el ID del recurso afectado
    ip_address      inet,
    user_agent      text,
    result          text NOT NULL,         -- 'success', 'denied', 'error'
    metadata        jsonb,                 -- contexto adicional (sin PII en sí mismo)
    -- inmutabilidad:
    CHECK (occurred_at <= now())
);

-- Permisos: solo el rol app puede INSERT; nadie puede UPDATE ni DELETE
REVOKE UPDATE, DELETE ON shared.audit_log FROM PUBLIC;
GRANT INSERT, SELECT ON shared.audit_log TO app_oms;

CREATE INDEX audit_log_resource_idx
  ON shared.audit_log (resource_type, resource_id, occurred_at);
CREATE INDEX audit_log_actor_idx
  ON shared.audit_log (actor_id, occurred_at)
  WHERE actor_id IS NOT NULL;
```

**Backup de audit log:**

- Snapshot diario al bucket S3 con object lock (WORM — Write Once Read Many) durante 7 años. Inmutabilidad real al nivel del almacenamiento.
- Verificación de integridad mensual con checksums.

**Generación del audit log:**

- Middleware HTTP genera entradas para cada acceso a recursos PII.
- Capa de repositorio (en módulos que tocan PII) genera entradas para modificaciones y borrados.
- Eventos del dominio que tocan PII (`UserDataExportRequested`, `UserDataDeletionRequested`) generan entradas.

### 2 · Workflow de borrado en cascada (REG-GDPR-002)

Al recibir una solicitud de borrado del usuario:

```
1. Usuario solicita borrado (vía perfil de cuenta o email)
2. IAM publica UserDataDeletionRequested(userId, requestedAt)
3. Cada bounded context con datos del usuario reacciona:
   - orders: marca pedidos del usuario para anonimización (no borrado físico —
     los pedidos son registro contable que debe conservarse 4 años por
     normativa fiscal española, REG-IVA-002)
   - billing: anonimiza datos del cliente en facturas (mantiene la línea
     fiscal, oculta nombre/dirección)
   - iam: borra User aggregate completamente
   - catalog: nada (no almacena datos del usuario)
   - inventory: nada
   - payments: borra paymentMethodTokens; conserva paymentIntentIds (referencia
     opaca a Stripe, no PII)
4. Cada módulo emite UserDataAnonymized o UserDataDeleted al completar
5. iam invalida sesiones, tokens, MFA seeds
6. shared.audit_log registra cada paso
7. Al completar: IAM emite UserDeleted(userId, deletedAt)
8. Email de confirmación al usuario en última dirección registrada
   (antes de borrarla)
```

**Plazo:** **15 días** (la mitad del plazo legal de 30 días para tener margen ante incidencias).

**Job de verificación diario:** revisa que no haya solicitudes pendientes > 20 días. Alerta a SRE si las hay.

### 3 · Export de datos personales (FR-038)

Job asíncrono al recibir `UserDataExportRequested`:

1. Recopila datos del usuario en cada bounded context (vía puerto driving que cada módulo expone).
2. Genera un ZIP con CSV por categoría (perfil, pedidos, facturas, comunicaciones).
3. Sube a S3 con URL firmada de validez 7 días.
4. Email al usuario con la URL.
5. Tras 7 días, el archivo se borra automáticamente.
6. Audit log registra cada paso.

### 4 · Consent management (REG-GDPR-004)

El módulo `iam` mantiene tabla de consentimientos con versionado:

```sql
CREATE TABLE iam.user_consents (
    user_id           uuid NOT NULL,
    consent_type      text NOT NULL,        -- 'marketing', 'profiling', 'cookies_analytics', 'tos', 'privacy_policy'
    policy_version    text NOT NULL,        -- 'v3.2'
    granted           boolean NOT NULL,
    granted_at        timestamptz NOT NULL,
    ip_address        inet,
    PRIMARY KEY (user_id, consent_type, granted_at)
);
```

Al cambiar la política de privacidad o términos, se incrementa la versión y se solicita reconsent en el próximo login. El sistema sirve los términos correspondientes a cada versión.

## Consecuencias

### Positivas

- **REG-GDPR-002 cumplido** con margen (plazo interno 15 días, legal 30).
- **REG-GDPR-003 cumplido** con audit log inmutable a nivel de aplicación + WORM en backups.
- **REG-GDPR-004 cumplido** con consent versionado.
- **FR-038 cumplido** con flujo asíncrono y descarga firmada.
- **Auditoría inherente** — la trazabilidad sirve también para investigar incidentes de seguridad (REG-GDPR-005).
- **Cumplimiento mantenido durante el resto de operación** — no hay forma de "saltarse" el audit log porque está en el middleware obligatorio y los repositorios.

### Negativas

- **Audit log crece linealmente con la actividad** — coste de storage no despreciable. Estimación: ~5-10 GB/año.
- **Performance overhead** — cada request paga el coste de un INSERT extra. Mitigación: insert asíncrono cuando no es crítico, sincrono en accesos sensibles. Coste real: ~1-3% latencia adicional, dentro de NFR-PERF-*.
- **Anonimización de pedidos en lugar de borrado** introduce dualidad — los pedidos antiguos del usuario "desaparecen" desde el punto de vista del usuario pero existen contablemente. Mitigación: documentación explícita en política de privacidad.
- **Borrado en cascada cross-módulo es asincrono** — un usuario puede ver "datos parcialmente borrados" durante minutos. Aceptable dentro del plazo de 15 días; SLA interno garantiza completitud.
- **Workflow de borrado complejo** — muchos puntos de fallo (qué pasa si falla un módulo en mitad). Mitigación: outbox + idempotencia (ADR-009) garantiza eventual consistency.

## Alternativas descartadas

### A · Append-only mediante triggers de PostgreSQL

**Por qué se descartó parcialmente:**
- El trigger evita UPDATE/DELETE pero un superusuario puede deshabilitar triggers.
- Se complementa con permisos REVOKE explícitos (decisión actual).

### B · Audit log en sistema externo (CloudWatch, Splunk, ELK)

**Por qué se descartó:**
- Pierde transaccionalidad: el audit log podría disociarse del cambio que registra.
- Para REG-GDPR-003 se necesita persistencia controlada por nosotros con cadena de custodia clara.
- Se complementa con observabilidad (logs operativos van a Loki, audit log va a la BD).

### C · Borrado físico inmediato (sin anonimización)

**Por qué se descartó:**
- REG-IVA-002 obliga a conservar facturas 4 años. Borrar físicamente al usuario rompería la integridad de las facturas.
- Anonimización es la solución estándar para reconciliar GDPR e IVA.

### D · Crypto-shredding (cifrar PII por usuario y borrar la clave)

**Por qué se considera:**
- Permite borrado "lógico" instantáneo conservando estructura.
- Más complejo de implementar correctamente.
- Decisión: **no implementado en V1** pero documentado como mejora futura. Si el volumen de solicitudes de borrado se vuelve masivo (señal: > 100/día), reabrir esta decisión.

### E · Tercerizar compliance GDPR a un proveedor (OneTrust, Privacera)

**Por qué se descartó:**
- Costoso para nuestro tamaño (~30-100K €/año en licencias).
- Acopla a un proveedor para algo que es responsabilidad propia.
- Aporta plantillas y reportes pero no la implementación técnica subyacente.

## Re-evaluación

Esta decisión se debe revisar cuando:

- El **volumen de solicitudes de borrado** supere ~100/día — evaluar crypto-shredding.
- Aparezca **regulación sectorial adicional** (ej. IA Act, NIS2 si aplica) que exija más capacidades de auditoría.
- Llegue una **breach de datos** — el incidente revelará qué partes del audit log fueron útiles y cuáles eran ruido.
- El **audit log crezca > 50GB** — particionar por mes y archivar particiones antiguas.

## Referencias

- ADR previos: [ADR-001](ADR-001-monolito-modular.md), [ADR-004](ADR-004-postgresql-multi-az.md), [ADR-009](ADR-009-outbox-pattern.md)
- Restricciones cumplidas: REG-GDPR-002, REG-GDPR-003, REG-GDPR-004, FR-038

---

> 💡 **NOTA PEDAGÓGICA — Vídeos 1 y 6**
>
> Este ADR es uno de los más densos del proyecto porque cubre varios temas a la vez:
>
> 1. **Restricciones inflexibles (V1)** — REG-GDPR-* dictan qué hay que hacer; el ADR documenta el cómo.
>
> 2. **Eventos de dominio + outbox (V6, ADR-009)** — el workflow de borrado se basa en eventos cross-módulo. Se ve cómo los patrones se componen: borrado solicitado → evento → suscriptores reaccionan → al completar emiten propios eventos.
>
> 3. **Cumplimiento como propiedad cross-cutting** — el audit log no vive en un módulo, vive en `shared/`. Esto rompe ligeramente la pureza de bounded contexts pero es justificado: la auditoría es transversal por naturaleza.
>
> Lección operativa: **GDPR no se "implementa" en el último sprint**. Cada decisión arquitectónica anterior (esquemas separados, outbox, audit log) se diseñó pensando en cumplir esto. Si llegas al sprint 30 y descubres que el sistema no es auditable, refactorizarlo es un proyecto de meses.
>
> Pregunta de examen: ¿qué pasa si un módulo nuevo se añade en 6 meses y olvida loggear accesos a PII? Respuesta: los tests de cumplimiento (que verifican que cualquier acceso a PII produce una entrada en `shared.audit_log`) lo detectan en CI antes del merge.
