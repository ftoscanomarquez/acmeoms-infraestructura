# Post-mortems del runbook: TODO_TITULO

> Aquí documentas la **evolución del runbook** a lo largo del tiempo.
> Cada vez que este incidente vuelve a ocurrir, el runbook se actualiza
> hacia más automatización. Eso es lo que un equipo SRE maduro hace.
>
> **Mínimo requerido:** 3 versiones (V1 → V2 → V3) que muestran el camino
> de "mitigación manual" a "automatizada/preventiva".

---

## Versión 1 — Mitigación manual (PM #1)

**Fecha del incidente:** TODO
**Duración del incidente:** TODO (T_detección → T_resolución)
**Detectado por:** TODO (alerta automática, queja de usuario, monitorización casual…)
**On-call:** TODO

### Lo que ocurrió
TODO 2-3 frases. ¿Qué se rompió, qué impacto tuvo?

### Cómo se mitigó
TODO descripción de la mitigación, **tal y como la improvisó el on-call** (sin runbook aún).
> Ej: "El on-call vio el dashboard, se conectó vía SSH al servidor, hizo `ps aux | grep`, identificó el proceso problemático y lo killeó."

### Aprendizajes y acciones
- TODO acción 1 (ej: "crear el runbook v1 con los pasos exactos que improvisé")
- TODO acción 2

### Versión 1 del runbook tras este post-mortem
TODO copia/pega aquí el contenido del runbook tal como quedó después.

---

## Versión 2 — Diagnóstico y comandos exactos (PM #2)

**Fecha del incidente:** TODO (típicamente semanas o meses después)
**Duración del incidente:** TODO (suele bajar respecto a V1 porque ahora hay runbook)

### Qué se vio durante esta segunda ocurrencia
TODO ¿el runbook V1 sirvió? ¿qué le faltó?
> Ej: "El on-call siguió los pasos del runbook pero tuvo que buscar la sintaxis exacta de `kubectl scale` en internet. Perdió 4 minutos."

### Qué cambió en el runbook (V1 → V2)
- TODO mejora 1 (ej: "comandos exactos, no genéricos")
- TODO mejora 2 (ej: "añadido paso de verificación con métrica concreta")
- TODO mejora 3

### Acciones derivadas
- TODO. Ej: "documentar el patrón en la wiki del equipo."
- TODO. Ej: "evaluar automatización del paso 2."

---

## Versión 3 — Automatización preventiva (PM #3)

**Fecha del incidente:** TODO

### Qué pasó esta tercera vez
TODO. **Ojo:** lo ideal es que NO haya tercera vez, porque el runbook V2 se habrá ejecutado preventivamente o el equipo habrá hecho un cambio estructural que elimine el problema.
> Ej: "Se disparó la alerta a las 9:00 de un lunes. La automatización en cron rotó las conexiones zombi 5 minutos antes; el incidente no llegó a impactar a ningún usuario."

### Qué cambió en el runbook (V2 → V3)
- TODO. Ej: "los pasos manuales 1 y 2 se ejecutan ahora vía cron preventivo a las 8:55."
- TODO. Ej: "la alerta principal cambia de severity=critical a severity=warning porque la automatización la previene."

### El runbook como script
> Si llegaste a automatizar uno de los runbooks, enlaza aquí el script.

- Script: `../../scripts/TODO-script-name.sh` (o `.py`)
- Cron: `TODO_EXPRESION_CRON` ejecutado por `TODO_OWNER`

### Métrica del runbook ahora
| | V1 | V2 | V3 |
|---|---|---|---|
| Veces disparado por incidente real | TODO | TODO | 0 (preventivo) |
| Tiempo medio de mitigación | TODO min | TODO min | 0 (no impacto) |
| Toil del on-call | Alto | Medio | Cero |

---

## Conclusión: la evolución del runbook

TODO un párrafo breve sobre cómo se ve ahora la operación del incidente original, y qué pasó en el equipo cuando hicieron este recorrido.
> Ej: "Lo que empezó como un incidente que despertaba al on-call cada tres semanas
> es ahora un cron silencioso que nadie mira. El equipo recuperó X horas/sprint
> que antes se iban en gestionar esto."
