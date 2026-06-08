# Runbooks

> Cada subcarpeta es un runbook independiente con sus 3 artefactos:
> `runbook.md`, `alert.yaml`, `post-mortems.md`.

## Estructura por runbook

```
01-db-pool-saturated/
├── runbook.md       ← el procedimiento (lo lee el on-call)
├── alert.yaml       ← la regla Prometheus que dispara el runbook
└── post-mortems.md  ← evolución V1 → V2 → V3 a lo largo del tiempo
```

## Criterios comunes (cualquier runbook tiene que cumplirlos)

1. **Trigger explícito** — la alerta exacta que lo dispara, con severity.
2. **Contexto** — qué impacta al usuario, qué NO afecta (acota el blast radius).
3. **Diagnóstico copiable** — comandos exactos en bloques de código. No "comprueba si la DB está sana", sino el `psql -c "SELECT..."`.
4. **Acciones ordenadas de menor a mayor impacto** — empiezas por lo barato y escalas.
5. **Acciones idempotentes** — ejecutarlas dos veces no empeora la situación.
6. **Verificación medible** — qué métrica concreta tiene que volver a normal, en qué ventana.
7. **Rollback** — qué deshaces si la mitigación empeoró las cosas.

## Catálogo

| ID | Nombre | Estado |
|---|---|---|
| 01 | db-pool-saturated | **OBLIGATORIO** |
| 02 | api-p95-high | a elegir |
| 03 | stripe-payment-gateway-degraded | a elegir |
| 04 | outbox-backlog-creciente | a elegir |
| 05 | redis-cache-down | a elegir |
| 06 | cloud-sql-disk-full | a elegir |
| 07 | canary-rollout-failed | a elegir |

Elige 2 del catálogo. Pueden ser de cualquier dificultad — la rúbrica no penaliza por elegir los fáciles, premia por hacerlos bien.

## Plantillas

`_template/` contiene los 3 ficheros base. Copia esa carpeta a `0X-tu-runbook/` y renombra los TODOs.
