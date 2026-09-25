# MIGRACION-EXPAND-CONTRACT.md — Cambio destructivo de schema sin downtime

**Bonus del enunciado** (sección 6): "Documentas (no implementas) el flujo para hacer un cambio destructivo de schema sin downtime". Este documento describe el proceso completo aplicado a un caso concreto y real del dominio de este proyecto: dividir la columna `orders.orders.delivery_address` (un único campo de texto libre) en columnas estructuradas.

No hay código de aplicación en este proyecto (ver la nota de alcance del `README.md` — el placeholder `server.js` no implementa lógica de negocio), así que esto es prosa deliberada, no una migración ejecutada. El escenario y el esquema usados son consistentes con `anexo-arquitectura/02-bounded-contexts.md` (bounded context `Orders`, módulo `orders`, esquema `orders.*`, entidad `Order` con `DeliveryAddress` como Value Object).

## El problema que resuelve expand-and-contract

Un cambio de schema "directo" — `ALTER TABLE orders.orders DROP COLUMN delivery_address, ADD COLUMN ...` en una sola migración — obliga a parar la aplicación durante el cambio: el código viejo (que todavía lee `delivery_address`) y el código nuevo (que espera las columnas nuevas) no pueden convivir contra el mismo schema. Con Cloud Run desplegando por revisiones (canary, ver `DEPLOYMENT.md`) y con OPS-007 exigiendo degradación suave, **nunca hay un instante donde "todo el tráfico" corre exactamente una versión del código** — durante un canary al 10%, dos versiones del código sirven tráfico real simultáneamente contra la misma base de datos. Un cambio destructivo directo rompería una de las dos.

Expand-and-contract resuelve esto separando el cambio en fases donde el schema siempre es compatible con **ambas** versiones del código a la vez.

## Escenario concreto: `orders.orders.delivery_address` (texto libre) → columnas estructuradas

Estado actual (hipotético, consistente con el modelo de `Order` del bounded context):

```sql
CREATE TABLE orders.orders (
  id              UUID PRIMARY KEY,
  user_id         UUID NOT NULL,
  status          TEXT NOT NULL,
  total           NUMERIC(10,2) NOT NULL,
  delivery_address TEXT NOT NULL,  -- "Calle Falsa 123, 28080 Madrid, España"
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Objetivo: reemplazar `delivery_address` (texto libre, sin estructura, imposible de filtrar por ciudad o validar el código postal) por el `DeliveryAddress` Value Object ya definido en `anexo-arquitectura/02-bounded-contexts.md` (`country`, `postal_code`, `city`, `street`, `recipient`) — un cambio de forma **destructivo**: la columna vieja debe desaparecer, no coexistir para siempre.

## Las 4 fases

### Fase 1 — EXPAND: añadir lo nuevo sin tocar lo viejo

```sql
ALTER TABLE orders.orders
  ADD COLUMN recipient    TEXT,
  ADD COLUMN street       TEXT,
  ADD COLUMN city         TEXT,
  ADD COLUMN postal_code  TEXT,
  ADD COLUMN country      TEXT;
```

Todas las columnas nuevas son **nullable** (sin `NOT NULL`, sin `DEFAULT` obligatorio) — el schema resultante es válido tanto para el código viejo (que ignora las columnas nuevas, nunca las escribe) como para el código nuevo (que ya puede empezar a escribirlas). Esta migración se aplica **antes** de desplegar ningún código nuevo, y es en sí misma no-destructiva: nada se pierde, nada se rompe.

Verificación de esta fase: `terraform plan`/migraciones de schema son responsabilidad de una herramienta de migraciones de la aplicación (ej. Flyway/Liquibase — fuera del alcance de este proyecto de infraestructura), pero el principio de "aplicar antes de desplegar" es el mismo que ya rige este proyecto para Cloud SQL: `deletion_protection` y `prevent_destroy` (`terraform/modules/database/main.tf`) garantizan que nadie destruye la instancia por accidente durante este proceso.

### Fase 2 — MIGRATE: backfill de los datos existentes

Con las columnas nuevas ya presentes, se rellenan para las filas existentes con un job de backfill (fuera de una transacción de aplicación — un script/migración que corre una sola vez, en lotes, para no bloquear la tabla):

```sql
UPDATE orders.orders
SET
  street      = split_part(delivery_address, ',', 1),
  postal_code = substring(delivery_address FROM '\d{5}'),
  city        = trim(split_part(split_part(delivery_address, ',', 2), ' ', 2)),
  country     = 'España'
WHERE street IS NULL;  -- procesar solo lo no migrado — reanudable si se interrumpe
```

En este punto conviven las dos representaciones para las filas viejas: `delivery_address` (el texto original, sin tocar) y las columnas nuevas (ya rellenas). El código **viejo** sigue leyendo/escribiendo `delivery_address` exclusivamente y sigue funcionando exactamente igual que antes. El código **nuevo**, desplegado ahora, escribe en las columnas nuevas para pedidos nuevos y puede leer de ambas si necesita atender un pedido creado antes de la migración (lógica de aplicación, tipo "leer columnas nuevas si existen, si no, parsear la columna vieja").

**Este es el punto donde el canary real de este proyecto entra en juego**: durante el despliegue del código nuevo vía `ansible/playbooks/deploy.yml` (10% de tráfico en producción — `group_vars/production.yml`), el 90% del tráfico sigue en el código viejo escribiendo solo `delivery_address`, y el 10% en el código nuevo escribiendo ambas representaciones. Ambos son válidos contra el mismo schema al mismo tiempo — es exactamente la propiedad que expand-and-contract garantiza, y la razón por la que este proyecto puede promover el canary de 10% a 100% gradualmente (`ansible/playbooks/promote-canary.yml`) sin que un pedido creado durante el canary quede en un estado inconsistente.

### Fase 3 — Validar que el 100% del tráfico ya usa las columnas nuevas

Antes de poder destruir nada, hay que confirmar dos cosas con evidencia real, no por supuesto:

1. **El código viejo ya no está sirviendo tráfico real.** En este proyecto, eso equivale a que `promote-canary.yml` haya llevado el canary al 100% (`ansible/playbooks/promote-canary.yml -e target_percent=100`) y que la revisión anterior ya no aparezca en `status.traffic[]` con ningún porcentaje — verificable con el mismo comando que ya usa `rollback.yml`:
   ```bash
   gcloud run services describe oms-production --region=europe-west3 \
     --flatten="status.traffic[]" --format="value(status.traffic.revisionName,status.traffic.percent)"
   ```
2. **No quedan filas sin backfillear.** Consulta de verificación antes de continuar:
   ```sql
   SELECT count(*) FROM orders.orders WHERE street IS NULL;
   -- Debe ser 0 antes de avanzar a la Fase 4
   ```

Si cualquiera de las dos falla, **no se avanza a la fase de contracción** — se mantiene el estado expandido (ambas representaciones conviviendo) todo el tiempo que haga falta. Esto es lo que distingue expand-and-contract de una migración con tiempo fijo: la duración de la fase "expandida" la decide la evidencia, no un cronograma.

### Fase 4 — CONTRACT: eliminar lo viejo

Solo una vez confirmado lo anterior, se hacen las columnas nuevas obligatorias y se elimina la columna vieja — ahora sí, en una migración que **es** destructiva, pero segura porque ya no hay ningún código en producción que dependa de lo que se está eliminando:

```sql
ALTER TABLE orders.orders
  ALTER COLUMN recipient    SET NOT NULL,
  ALTER COLUMN street       SET NOT NULL,
  ALTER COLUMN city         SET NOT NULL,
  ALTER COLUMN postal_code  SET NOT NULL,
  ALTER COLUMN country      SET NOT NULL;

ALTER TABLE orders.orders DROP COLUMN delivery_address;
```

Un rollback de código en este punto (`ansible/playbooks/rollback.yml`, que vuelve el 100% del tráfico a la revisión N-1) **ya no es seguro** si la revisión N-1 es anterior a la Fase 2 — el código viejo intentaría leer/escribir una columna que ya no existe. Esta es la razón real por la que expand-and-contract exige la validación explícita de la Fase 3 antes de contraer: una vez se ejecuta la Fase 4, se cierra la puerta al rollback de código hacia versiones pre-migración. Si existiera el riesgo de necesitar revertir el código más allá de ese punto, la Fase 4 se pospone.

## Resumen visual

```
Fase 1 (EXPAND)        Fase 2 (MIGRATE)         Fase 3 (VALIDAR)      Fase 4 (CONTRACT)
─────────────────      ──────────────────       ─────────────────    ──────────────────
+ columnas nuevas   →  código nuevo escribe   →  100% tráfico en   →  columnas nuevas
  (nullable)            ambas representaciones    código nuevo,       NOT NULL
  código viejo           código viejo sigue        0 filas sin        + DROP columna
  no se entera            usando solo la vieja      backfillear         vieja
                                                                     (sin vuelta atrás
                                                                      de código)
```

## Por qué esto encaja con las decisiones ya tomadas en este proyecto

- El canary progresivo real (`ci-cd.yml` deja 10%, `canary-decision.yml` decide subir o hacer rollback — ver `DEPLOYMENT.md`) es exactamente el mecanismo que hace *necesario* diseñar los cambios de schema de esta forma: con dos versiones de código sirviendo tráfico real simultáneamente, un cambio de schema no compatible con ambas rompería el 10% o el 90%, según cuál.
- `deletion_protection = true` + `lifecycle.prevent_destroy` en Cloud SQL (`terraform/modules/database/main.tf`) protegen la instancia completa contra un `terraform destroy`, pero no protegen contra un `DROP COLUMN` mal planificado dentro de la base de datos — expand-and-contract es la disciplina que cubre exactamente ese hueco, a nivel de la aplicación, no de la infraestructura.
- La Fase 3 de validación usa el mismo comando (`gcloud run services describe --flatten=status.traffic[]`) que ya está probado y documentado en `rollback.yml`/`promote-canary.yml` — no es una herramienta nueva, es el mismo mecanismo de observación del tráfico real que este proyecto ya construyó y verificó contra producción.
