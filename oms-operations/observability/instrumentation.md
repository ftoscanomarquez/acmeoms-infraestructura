# Plan de instrumentación del OMS

> Para cada módulo del OMS, qué se instrumenta y por qué.
> Cada métrica debe poder trazarse a un quality attribute de la spec.

---

## Regla guía (del Vídeo 1)

> **Si lo especificas, lo mides. Si lo mides, lo alertas.**

Cada fila de las tablas siguientes debe poder defenderse así:
"esta métrica existe porque la spec dice X, y la usamos para verificar Y."

---

## Módulo Catalog

| Quality attribute | Métrica | SLI derivado | Alerta asociada |
|---|---|---|---|
| TODO ej: NFR-PERF-002 (p95 < 250ms) | TODO ej: `http_duration_seconds{endpoint="/catalog"}` | TODO ej: histogram_quantile(0.95, ...) | TODO ej: `CatalogLatencyHigh` |
| NFR-PERF-001 (caché Redis funciona) | TODO ej: `redis_hits_total / (hits + misses)` | TODO | TODO |
| NFR-AVAIL-002 (sirve aunque DB falle) | TODO | TODO | TODO |

---

## Módulo Inventory

TODO 3-4 filas siguiendo el mismo patrón. Sugerencias de quality attributes a cubrir:
- Disponibilidad de `POST /stock/reserve`
- Latencia de la reserva atómica
- Detección de double-reserve (debería ser cero)

| Quality attribute | Métrica | SLI | Alerta |
|---|---|---|---|
| TODO | TODO | TODO | TODO |

---

## Módulo Orders

| Quality attribute | Métrica | SLI | Alerta |
|---|---|---|---|
| TODO disponibilidad `POST /orders` | TODO | TODO link a `slos-orders.md` SLO 1 | `OrdersAvailabilityBurnRate` |
| TODO latencia creación pedido | TODO | TODO | TODO |
| TODO transacciones ACID (rollback rate) | TODO | TODO | TODO |

---

## Módulo Payments

| Quality attribute | Métrica | SLI | Alerta |
|---|---|---|---|
| TODO disponibilidad autorización | TODO | TODO link a `slos-payments.md` | TODO |
| Salud externa de Stripe | TODO ej: `stripe_request_errors_total` | (no SLI propio, mide visibilidad) | `StripeDegraded` |

---

## Módulo Billing

TODO sigue patrón.

---

## Módulo IAM

TODO sigue patrón. Pista: éxito de login, latencia de tokens, intentos sospechosos.

---

## Infraestructura compartida

### Cloud SQL Postgres
| Métrica | Por qué | Alerta |
|---|---|---|
| `db_pool_in_use / db_pool_size` | Saturación de conexiones | `DBConnectionPoolSaturated` (runbook 01) |
| `pg_stat_database.deadlocks` | Detectar bloqueos | TODO |
| `disk_used_bytes / disk_size_bytes` | Prevenir disco lleno | `DBDiskUsageHigh` (runbook 06) |

### Memorystore Redis
| Métrica | Por qué | Alerta |
|---|---|---|
| TODO hit ratio | NFR-PERF-001 | TODO |
| TODO uptime | NFR-AVAIL-002 | `RedisDown` (runbook 05) |

### Cloud Run
| Métrica | Por qué | Alerta |
|---|---|---|
| TODO instancias activas | Escalado | TODO |
| TODO cold starts | Latencia | TODO |

---

## Logs estructurados

Todos los módulos del OMS emiten logs en formato JSON con los siguientes campos mínimos:

```json
{
  "ts":         "2026-01-15T10:23:47Z",
  "level":      "ERROR | WARN | INFO | DEBUG",
  "service":    "oms-orders | oms-payments | ...",
  "trace_id":   "abc123",
  "span_id":    "def456",
  "user_id":    "u_xxx",
  "request_id": "req_xxx",
  "event":      "TODO clave estandarizada",
  "...":        "campos específicos del evento"
}
```

TODO(alumno): justifica por qué incluyes/excluyes ciertos campos. Recuerda la regla PII: **no logear el contenido de campos personales sin enmascarar** (GDPR).

---

## Coste de la telemetría

TODO calcula el coste estimado mensual con cifras realistas:
- Logs: ~X GB/día × $Y/GB en Cloud Logging
- Métricas: ~Z series, gratis hasta Q activas en Cloud Monitoring
- Trazas: ~W trazas/mes con sampling al 1% en Cloud Trace

Si supera el presupuesto, **revisa el sampling** y el nivel de logs en producción.
