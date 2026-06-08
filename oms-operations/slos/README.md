# SLOs y política de error budget

> 2 SLOs (uno por módulo crítico) + política de error budget de una página.

## Ficheros

| Fichero | Qué contiene |
|---|---|
| `slos-orders.md` | SLO de disponibilidad y otro a elegir para el módulo Orders |
| `slos-payments.md` | SLO de disponibilidad de autorización (con consideración de Stripe) |
| `error-budget-policy.md` | Niveles 🟢🟡🔴⚫ con umbrales numéricos y consecuencias |

## Criterio del oficio

Un SLO bueno cumple las 4:
- Tiene un **SLI exacto** con numerador, denominador y ventana
- Mide lo que el **usuario** experimenta, no la salud de la infra
- Su **error budget** está calculado en minutos al mes (no es porcentaje abstracto)
- Tiene una **alerta de burn rate** que dispara antes del incumplimiento real
