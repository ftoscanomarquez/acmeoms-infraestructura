# Runbook: TODO_TITULO_DEL_INCIDENTE

> **Para qué sirve este template:** copia esta carpeta entera a `runbooks/0X-tu-runbook/` y rellena los TODO.
> **Regla del oficio:** este runbook se va a leer a las 3 AM, con un on-call que no tocó el sistema en 6 meses.
> Si requiere pensar, no es un runbook — es una nota.

---

## Trigger

**Alerta:** `TODO_NOMBRE_ALERTA` (severity: TODO_SEVERITY)
**Condición:** TODO una frase exacta. Ej: "p95 de `GET /search` > 500 ms durante 5 minutos consecutivos."
**Cuándo dispara:** TODO ej: "cuando burn rate del SLO supera 2× durante 1h."

---

## Contexto

**Qué impacto tiene:** TODO descripción del impacto al usuario en lenguaje de negocio.
> Ej: "los usuarios ven la página de catálogo más lenta de lo normal; algunos pueden abandonar el flujo de compra."

**Qué NO afecta:** TODO acota el blast radius.
> Ej: "no afecta a `/orders` ni al checkout. Pagos siguen funcionando."

**Pre-requisitos para diagnosticar:** TODO accesos, credenciales, dashboards a tener abiertos.
> Ej: "necesitas: acceso a Cloud Console del proyecto `oms-production`, credenciales `kubectl` al cluster, dashboard de Grafana `oms-overview`."

---

## Diagnóstico (en orden, ejecuta y mira)

> Los comandos están **copiables**. No los reescribas a las 3 AM.

### 1. TODO ¿Qué pregunta respondes con este comando?

```bash
# TODO comando exacto, no genérico
TODO_COMANDO_AQUI
```

**Si la salida es X:** TODO qué significa.
**Si la salida es Y:** TODO qué significa y a qué paso pasar.

### 2. TODO Siguiente pregunta

```bash
TODO_COMANDO_AQUI
```

**Interpretación:** TODO.

### 3. TODO Tercera pregunta

```sql
-- Si necesitas SQL contra la BD
TODO_QUERY_AQUI;
```

**Interpretación:** TODO.

---

## Acciones (de menor a mayor impacto, idempotentes)

> Empieza por la acción de menor coste/riesgo. Solo escalas si la anterior no resolvió.

### Acción 1: TODO (impacto: bajo · reversible)

```bash
TODO_COMANDO_DE_LA_ACCION
```

**Qué hace:** TODO una frase.
**Por qué primero:** TODO. Ej: "no requiere downtime, es local al pod afectado."
**Cuándo NO ejecutarla:** TODO. Ej: "si ya se ejecutó hace < 5 min y no funcionó, salta a la acción 2."

### Acción 2: TODO (impacto: medio · reversible con rollback)

```bash
TODO_COMANDO
```

**Qué hace:** TODO.
**Coste de rollback:** TODO (ver sección Rollback).

### Acción 3: TODO (impacto: alto · usar como último recurso)

```bash
TODO_COMANDO
```

**Qué hace:** TODO.
**Coste:** TODO. Ej: "fuerza failover de la BD primaria, ~30s de error rate elevado."
**Quién aprueba:** TODO si requiere approval — engineering manager, CTO, etc.

---

## Verificación

> Sin verificación medible, declarar "ya está arreglado" es esperanza, no diagnóstico.

**Métrica que tiene que volver a normal:** TODO
> Ej: `histogram_quantile(0.95, ...)` debe quedar por debajo de 300 ms.

**Ventana de observación:** TODO
> Ej: "durante 10 minutos consecutivos."

**Cómo confirmas:**
1. Mira el dashboard TODO_NOMBRE_DASHBOARD
2. Espera el tiempo de la ventana
3. Confirma en el canal `#incident-response` que has cerrado el incidente

---

## Rollback

> ¿Qué deshaces si la mitigación empeoró las cosas?

**De la Acción 1:** TODO. Ej: "automática, no requiere intervención (es local al pod)."

**De la Acción 2:** TODO. Ej:
```bash
# Re-scale al número original
kubectl scale deploy/oms-api --replicas=12
```

**De la Acción 3:** TODO. Ej: "no hay rollback automático del failover; ver runbook `db-promote-replica`."

---

## Después del incidente

- [ ] Anota la duración total (T_detección - T_resolución) en el ticket de incidente
- [ ] Si la acción 1 no funcionó, abre PR para añadir un paso de diagnóstico que lo habría detectado antes
- [ ] Si tuviste que llegar a la acción 3, programa post-mortem dentro de 48h
- [ ] Si el runbook tuvo que ser improvisado, actualízalo aquí mismo (este documento es living)

---

## Enlaces relacionados

- Alerta YAML: `alert.yaml`
- Post-mortems históricos: `post-mortems.md`
- SLO que dispara este runbook: `../../slos/slos-TODO.md`
- Dashboard: TODO_URL
