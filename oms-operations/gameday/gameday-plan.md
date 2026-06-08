# GameDay plan — TODO_NOMBRE_DEL_ESCENARIO

> Diseña un GameDay que valide UNO de tus runbooks.
> Recomendado: usa el runbook obligatorio `01-db-pool-saturated` para tener
> garantía de cobertura completa.

---

## Identificación

**GameDay #:** TODO
**Fecha y duración:** TODO (sugerencia: 2 horas — 30 min preparación, 1 h ejecución + recuperación, 30 min post-mortem en caliente)
**Entorno:** TODO (pre-producción, **NO producción**)
**Owner:** TODO equipo organizador
**Runbook que valida:** `../runbooks/TODO/`

---

## Hipótesis

TODO una sola frase con lo que esperamos que pase.
> Ej: "El runbook `01-db-pool-saturated` permite al on-call mitigar el incidente en menos de 5 minutos siguiendo los pasos al pie de la letra, sin necesidad de improvisar."

**Métricas que validan la hipótesis (criterio de éxito):**
- TODO. Ej: "El SLO de orders se mantiene en verde durante todo el ejercicio."
- TODO. Ej: "El time-to-mitigation desde la alerta es < 5 minutos."
- TODO. Ej: "El on-call solo consulta el runbook y los dashboards — cero búsquedas en internet."

---

## Escenario

**Cómo provocamos el fallo:**
TODO comando exacto + herramienta.
> Ej: "Lanzar un job batch que abra 80 conexiones idle simultáneas contra Cloud SQL desde `gameday-job.py` en la VM `demo-vm`."

**Cuándo lo lanzamos:**
TODO. Ej: "T+0 (inicio del GameDay)."

**Pre-flight checks:**
- [ ] Tráfico sintético al X% del pico real corriendo en pre-prod
- [ ] On-call shadow confirmado y disponible
- [ ] Dashboards de Grafana abiertos: `oms-db-overview`, `oms-overview`
- [ ] Canal de comunicación abierto: `#gameday-TODO`

---

## Alcance acotado

**SÍ se toca:**
- TODO. Ej: "Cloud SQL `oms-db-staging` en europe-west3"
- TODO. Ej: "Pool de conexiones del módulo `orders` en pre-producción"

**NO se toca (innegociable):**
- TODO. Ej: "Nada en producción"
- TODO. Ej: "Cloud SQL de `payments` (otro equipo)"
- TODO. Ej: "Red interna, firewalls, IAM"

---

## Métricas a observar (antes / durante / después)

| Métrica | Baseline (antes) | Esperada (durante) | Verificación (después) |
|---|---|---|---|
| TODO pool usage | < 30% | TODO ej: pico al 95-100% | TODO < 70% durante 10 min |
| TODO p95 latency orders | TODO ej: 180ms | TODO ej: pico a 500ms+ | TODO vuelta a baseline |
| TODO error rate POST /orders | TODO ej: 0.1% | TODO ej: pico a 2-5% | TODO < 0.5% |
| TODO budget consumido | TODO % | TODO espera incremento | TODO documentar |

---

## Escape hatch

**Aborto inmediato si:**
- TODO. Ej: "error rate > 10% durante > 2 min"
- TODO. Ej: "el incidente se extiende fuera del alcance acotado"
- TODO. Ej: "algún sistema en producción se ve afectado"

**Recuperación de emergencia:**
TODO comando.
> Ej: `python gameday-job.py --stop --release-all` para cerrar las conexiones inyectadas.

---

## Checklist temporal (minuto a minuto)

```
T-30  Equipo en sala. Dashboards abiertos. Tráfico sintético corriendo.
T-15  Verificación pre-flight completada.
T-5   On-call shadow recibe brief: "vas a ver una alerta en breve, sigue el runbook."

T+0   Game Master ejecuta el escenario.
T+0   Observadores arrancan reloj. Toman notas.

T+0:00–05:00  Observación activa. NADIE interviene. Solo observamos cómo el on-call usa el runbook.
T+05:00–30:00 Recuperación. Si el on-call no resolvió, Game Master ejecuta el rollback de emergencia.

T+30:00–60:00 Post-mortem en caliente con todo el equipo.
```

---

## Roles

| Rol | Persona | Responsabilidad |
|---|---|---|
| Game Master | TODO | Ejecuta el escenario, monitoriza escape hatch |
| Observador 1 | TODO | Cronómetro + nota detallada de cada acción del on-call |
| Observador 2 | TODO | Foco en métricas — qué se desvía, cuándo, cuánto |
| On-call shadow | TODO | El que sigue el runbook como si fuera real |
| Comunicación | TODO | Mantiene #gameday-TODO informado, avisa si algo se sale del alcance |

---

## Post-mortem (a rellenar tras el ejercicio)

### Resumen
TODO 2 frases sobre cómo fue.

### Lo que funcionó del runbook
TODO bullets.

### Lo que NO funcionó / falta del runbook
TODO bullets. (Esto es lo más valioso del GameDay.)

### Acciones derivadas
| # | Acción | Owner | Due |
|---|---|---|---|
| 1 | TODO | TODO | TODO |
| 2 | TODO | TODO | TODO |

### Versión nueva del runbook
- [ ] Aplicar las acciones derivadas al runbook
- [ ] Crear nuevo post-mortem (V_N+1) en `../runbooks/TODO/post-mortems.md`
- [ ] Programar siguiente GameDay con el mismo escenario en T+3 meses para verificar mejora
