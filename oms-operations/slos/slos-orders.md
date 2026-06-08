# SLO del módulo Orders

> Un SLO para el endpoint más crítico del OMS: la creación de pedidos.
> Si se rompe esto, hay clientes sin poder comprar = pérdida directa.

---

## SLO 1 · Disponibilidad de `POST /orders`

**Enunciado (una sola frase):**
TODO. Pista: estructura "X% de las peticiones <Y> responden con código <Z> durante la ventana <W>".
> Ejemplo: "99,5% de las peticiones `POST /orders` devuelven un código != 5xx en una ventana rolling de 28 días."

**Por qué importa al usuario:**
TODO. Pista: el usuario que recibe un 5xx no completa la compra. Pérdida de ingreso directa.

### SLI que lo instrumenta

**Numerador (good events):** peticiones que NO son 5xx.
**Denominador (valid events):** peticiones válidas — excluyes health checks (`GET /healthz`) y 4xx del cliente.
**Ventana:** 28 días rolling.

```promql
# SLI canónico: good events / valid events
sum(rate(http_requests_total{
  job="oms-orders",
  endpoint="/orders",
  method="POST",
  code!~"5..",
  code!~"4.."
}[28d]))
/
sum(rate(http_requests_total{
  job="oms-orders",
  endpoint="/orders",
  method="POST",
  code!~"4.."
}[28d]))

# El resultado es un número entre 0 y 1.
# SLO: este número >= 0.995
```

### Error budget calculado

TODO los números.

| Cálculo | Valor |
|---|---|
| Tráfico medio estimado | TODO RPS |
| Peticiones totales en 28d | TODO |
| Error budget (0,5%) en peticiones | TODO |
| Equivalente en minutos de caída total al mes | TODO |

> Pista: si tráfico = 100 RPS, peticiones 28d ≈ 242 millones; budget = 1,21 M peticiones = ~201 min al mes.

### Burn rate

```promql
# Alerta si gastas > 2% del error budget en 1h
(
  sum(rate(http_requests_total{job="oms-orders", endpoint="/orders", method="POST", code=~"5.."}[1h]))
  /
  sum(rate(http_requests_total{job="oms-orders", endpoint="/orders", method="POST", code!~"4.."}[1h]))
)
> 0.02 * 0.005
```

---

## SLO 2 · TODO_ELIGE

> Añade aquí un segundo SLO del módulo Orders. Sugerencias:
> - Latencia del p95 de `POST /orders`
> - Frescura de los datos vistos en `/orders/{id}` tras la creación
> - Tiempo desde `PaymentCaptured` hasta `OrderConfirmed`

TODO. Sigue el mismo patrón: enunciado · por qué importa al usuario · SLI con PromQL · error budget.

---

## Notas
- Estos SLOs son **internos** del equipo (no SLA con cliente).
- Cuando producto pida cambiar 99,5% por 99,9%, mira el error budget: 99,9% son 40 min/mes vs 201 min/mes. Pregúntale si está dispuesto a invertir 3-5× en infra y proceso para ese cambio.
