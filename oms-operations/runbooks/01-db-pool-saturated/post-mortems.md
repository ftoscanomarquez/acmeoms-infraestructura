# Post-mortems del runbook: db-pool-saturated

> Mínimo 3 versiones que muestren la evolución del runbook hacia más automatización.
> La historia debe ser realista: por qué ocurrió, qué se hizo, qué se cambió, qué se aprendió.

---

## Versión 1 — Mitigación manual (PM #1)

**Fecha del incidente:** TODO (ej: lunes 10 marzo 2026, 09:12 CET)
**Duración del incidente:** TODO (ej: 23 minutos desde la primera petición caída hasta verificación verde)
**Detectado por:** TODO (ej: alerta automática a las 09:07, on-call respondió a las 09:12)
**On-call:** TODO

### Lo que ocurrió
TODO una descripción honesta. Por ejemplo:
> "El lunes a las 9:00 se lanzó la campaña de email de la semana. Eso generó un pico de pedidos del 400% sobre el tráfico medio. Las apps de `orders` y `payments` abrieron conexiones masivamente. A las 9:07 el pool de Cloud SQL estaba al 95%. A las 9:09 al 100% y empezaron los errores 5xx."

### Cómo se mitigó (improvisado, sin runbook)
TODO descripción de lo que hizo el on-call.
> "El on-call vio el dashboard, entró en la consola de Cloud SQL, abrió pg_stat_activity desde la UI, identificó que había 80 conexiones idle de hace > 1h (sesiones zombi). Las terminó una a una desde la UI. A las 9:25 el pool había bajado al 60% y los errores cesaron."

### Aprendizajes y acciones
- TODO. Ej: "El on-call tardó 5 min solo en recordar cómo abrir pg_stat_activity desde la consola. Necesitamos runbook con SQL exacto."
- TODO. Ej: "Las conexiones idle > 1h no deberían existir. Investigar por qué la app no las cierra."
- TODO. Ej: "La campaña de email tendría que avisar al equipo de orders 24h antes."

### Versión 1 del runbook tras este post-mortem
> Aquí se pega la versión más temprana del runbook. Sin lujos. Solo los pasos que sirvieron.

**Runbook v1 (texto literal):**
> "Si la alerta DBConnectionPoolSaturated dispara: ir a la consola de Cloud SQL,
> abrir pg_stat_activity, buscar conexiones idle > 1h, terminarlas."

(Eso es todo. Es muy poco. Por eso hay V2.)

---

## Versión 2 — Diagnóstico y comandos exactos (PM #2)

**Fecha del incidente:** TODO (ej: lunes 7 abril 2026, 09:03 CET)
**Duración del incidente:** TODO (ej: 8 minutos)

### Qué se vio durante esta segunda ocurrencia
TODO. Por ejemplo:
> "Volvió a pasar el lunes siguiente al lanzamiento de la campaña. El on-call esta vez sí tenía el runbook v1, pero le faltaba el SQL exacto. Tuvo que buscar `pg_terminate_backend` en internet, lo que le costó 4 minutos."

### Qué cambió en el runbook (V1 → V2)
- TODO. Ej: "Comandos SQL exactos y copiables, no solo descripción."
- TODO. Ej: "Añadido paso de diagnóstico previo (¿quién consume el pool?)."
- TODO. Ej: "Acciones ordenadas de menor a mayor impacto."
- TODO. Ej: "Verificación con métrica concreta (< 70% durante 10 min)."

### Acciones derivadas
- TODO. Ej: "Crear un alias kubectl para conectar al pgbouncer rápido."
- TODO. Ej: "Investigar root cause: la app no está cerrando conexiones tras el `commit`. Bug ticket OMS-1234."
- TODO. Ej: "Evaluar cron preventivo que mate conexiones idle > 30 min cada hora."

---

## Versión 3 — Automatización preventiva (PM #3)

**Fecha:** TODO (ej: el incidente NO ocurre el lunes 12 mayo)

### Qué pasó (o, mejor, qué NO pasó)
TODO. Lo ideal es que esta tercera versión describa la **NO ocurrencia** del incidente.
> "El cron preventivo (`kill-idle-connections.sh` cada hora desde el sprint pasado) eliminó las conexiones idle largas. La campaña de email del lunes 12 generó el mismo pico que las anteriores, pero el pool no llegó al 85%. Cero alertas. Cero usuarios afectados."

### Qué cambió en el runbook (V2 → V3)
- TODO. Ej: "Los pasos manuales 1 y 2 del runbook se ejecutan automáticamente en cron."
- TODO. Ej: "La alerta cambia de severity=critical a severity=warning para esta condición específica."
- TODO. Ej: "Se añade nueva alerta crítica si el cron preventivo falla."
- TODO. Ej: "El bug OMS-1234 (conexiones no cerradas tras commit) sigue abierto pero la mitigación reduce el síntoma a cero."

### El runbook como script

```bash
# scripts/kill-idle-connections.sh
#!/usr/bin/env bash
set -euo pipefail

PROJECT="oms-production"
DB="oms"

psql -h "${PG_HOST}" -U oms_admin -d "${DB}" <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state='idle'
  AND state_change < now() - interval '30 min'
  AND datname = '${DB}';
SQL

echo "Cleanup complete at $(date -Iseconds)"
```

- **Cron:** `0 * * * * /opt/oms-ops/scripts/kill-idle-connections.sh`
- **Owner:** equipo SRE
- **Métrica de salud del script:** `cron_run_success_timestamp` debe actualizarse cada hora

### Métrica del runbook a lo largo de la evolución

| | V1 (manual) | V2 (comandos) | V3 (preventivo) |
|---|---|---|---|
| Veces disparado por incidente real | 1 | 1 | 0 |
| Tiempo medio de mitigación | 23 min | 8 min | 0 (no impacto) |
| Toil del on-call | Alto | Medio | Cero |
| Margen de mejora siguiente | Comandos exactos | Automatización | Arreglar bug OMS-1234 |

---

## Conclusión

TODO un párrafo breve sobre cómo este patrón —V1 manual → V2 con dientes → V3 automatizado— es exactamente el ciclo del Vídeo 3.
> Ej: "El incidente que despertaba al on-call cada tres semanas es ahora un cron silencioso que reporta cero impacto. El equipo recuperó ~2h/semana de gestión y, lo más importante, dejó de tener que escalar el equipo de guardia para cubrir lunes a las 9."
