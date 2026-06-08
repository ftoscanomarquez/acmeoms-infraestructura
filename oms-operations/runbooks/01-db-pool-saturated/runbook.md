# Runbook: DB Connection Pool Saturado (Cloud SQL Postgres)

> **OBLIGATORIO** — todos los alumnos tienen que entregar este runbook completo.
> Es el ejemplo canónico de "incidente recurrente con causa identificable y mitigación reversible".

---

## Trigger

**Alerta:** `DBConnectionPoolSaturated` (severity: critical)
**Condición:** `db_pool_in_use / db_pool_size > 0.9` durante 3 minutos consecutivos.
**Cuándo dispara:** TODO completa con la descripción operativa.
> Pista: ocurre típicamente con picos de tráfico o jobs batch mal dimensionados.

---

## Contexto

**Qué impacto tiene:**
TODO descripción en lenguaje de negocio. Cuando el pool llega al 100%, las nuevas conexiones empiezan a fallar y los usuarios ven errores 5xx esporádicos en operaciones que escriben datos.

**Qué NO afecta (todavía):**
TODO. Pista: las lecturas que usan cache de Redis siguen funcionando. El módulo de catálogo no se ve afectado hasta que el TTL expire y necesite refrescar.

**Pre-requisitos:**
- TODO permisos `roles/cloudsql.client` sobre el proyecto
- TODO acceso a `psql` con las credenciales del Secret Manager
- TODO dashboard `oms-db-overview` en Grafana

---

## Diagnóstico (en orden)

### 1. ¿Quién está consumiendo el pool ahora mismo?

```bash
# TODO conexión a la BD
# (pista: usa cloud_sql_proxy o conexión privada vía VPC)

psql -h TODO_HOST -U oms_app -d oms -c "
  SELECT application_name, count(*) AS conexiones
  FROM pg_stat_activity
  WHERE datname = 'oms'
  GROUP BY application_name
  ORDER BY conexiones DESC;
"
```

**Si una sola aplicación domina (>70% del pool):** TODO probablemente esa app tiene un leak o un job mal dimensionado. Salta a Acción 3.
**Si está distribuido entre todas las apps:** TODO el problema es de capacidad, no de un consumidor concreto. Salta a Acción 2.

### 2. ¿Hay conexiones idle largas? (zombies)

```bash
TODO_COMANDO
# Pista: pg_stat_activity tiene state='idle' y state_change
```

**Si hay > 20 conexiones idle con state_change > 10 min:** ejecuta Acción 1.

### 3. ¿Hay alguna query bloqueando?

```bash
TODO_COMANDO
# Pista: pg_stat_activity tiene wait_event_type='Lock'
```

**Si encuentras una query bloqueante:** TODO interpretación.

---

## Acciones (de menor a mayor impacto)

### Acción 1: Matar conexiones idle > 10 min (impacto: bajo · reversible)

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state='idle'
  AND state_change < now() - interval '10 min'
  AND datname = 'oms';
```

**Qué hace:** TODO una frase. Pista: termina las sesiones que no han estado activas y libera espacio en el pool.
**Por qué primero:** TODO. Pista: es local a la BD, no requiere redeploy, y solo afecta a sesiones que llevaban inactivas suficiente tiempo.
**Cuándo NO ejecutarla:** TODO.

### Acción 2: Escalar el pool de conexiones de la app (impacto: medio · requiere redeploy)

TODO instrucción paso a paso.
> Pista: editar `connection_pool_size` en el deployment de Cloud Run (`max-instances` y `concurrency`) y aplicar con `gcloud run services update`.

```bash
gcloud run services update oms-orders \
  --region=europe-west3 \
  --update-env-vars=DB_POOL_SIZE=50
```

**Coste:** TODO. Pista: ~30 segundos de rolling update.

### Acción 3: Killear job batch responsable (impacto: alto · usar si la Acción 1 identificó al culpable)

TODO instrucción.
> Pista: típicamente un `Kubernetes Job` o un `Cloud Scheduler` ejecutándose con concurrencia descontrolada.

**Quién aprueba:** TODO.
**Comunicación:** notifica al canal del equipo dueño del job antes de killearlo.

---

## Verificación

**Métrica que tiene que volver a normal:**
```promql
TODO_PROMQL
# Pista: el ratio db_pool_in_use / db_pool_size debe bajar y mantenerse < 0.7
```

**Ventana de observación:** 10 minutos consecutivos.

**Cómo confirmas:**
1. Mira el panel "Pool usage" en Grafana `oms-db-overview`
2. Confirma que la métrica está por debajo de 70% durante 10 min
3. Comunica en `#incident-response`: "DB pool back to normal, X% utilization stable for 10min, closing incident."

---

## Rollback

- **Acción 1 (kill idle):** no hay rollback necesario. Las apps reconectarán solas en su próximo `BEGIN`.
- **Acción 2 (escalar pool):** si genera carga insostenible en la BD, vuelve al valor original con la misma cli. Coste: otro rolling update.
- **Acción 3 (kill job):** si el job era crítico, re-encolarlo manualmente. Documenta en el ticket de incidente.

---

## Después del incidente

- [ ] Anota duración total y qué acción fue suficiente (1, 2 o 3)
- [ ] Si llegaste a la Acción 3: abre post-mortem dentro de 48h (incidente recurrente, hay que entender el patrón)
- [ ] Si la Acción 1 fue suficiente: actualiza el cron de "kill idle preventivo" si aplica
- [ ] Si la métrica del pool sube de nuevo en < 1h: NO cerrar incidente, escalar

---

## Enlaces relacionados

- Alerta YAML: `alert.yaml`
- Post-mortems históricos: `post-mortems.md`
- SLO de disponibilidad de `/orders`: `../../slos/slos-orders.md`
- Runbook relacionado: `06-cloud-sql-disk-full` (si el origen del problema es escritura excesiva)
