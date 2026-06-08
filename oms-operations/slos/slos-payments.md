# SLO del módulo Payments

> Payments tiene una particularidad: depende de Stripe (externo). Eso cambia
> cómo se definen los SLOs, porque parte de la disponibilidad NO está en tus manos.

---

## SLO · Disponibilidad de autorización de pagos

**Enunciado:**
TODO. Pista: misma estructura que orders, pero ojo con cómo cuentas los fallos cuando Stripe está caído.
> Sugerencia: "99,0% de las peticiones de autorización de pago completan en < 3s con código de éxito de Stripe, en una ventana de 28 días."

**Por qué importa al usuario:**
TODO. El usuario que ve "no pudimos procesar tu pago" abandona el checkout.

### SLI

**Numerador (good events):** TODO.
**Denominador (valid events):** TODO. Pista: ¿cuentas como "valid" las peticiones donde Stripe respondió 5xx, o las excluyes? Argumenta tu decisión en la sección de Notas.
**Ventana:** 28 días.

```promql
TODO_PROMQL
```

### Error budget calculado

TODO el cálculo.

### Tratamiento de fallos externos (Stripe)

TODO discusión. Pista:
- Opción A: los fallos de Stripe **cuentan** contra tu SLO. Te empuja a tener circuit breaker, retries, queue para reintento, fallback.
- Opción B: los fallos de Stripe **no cuentan**. Más fácil de cumplir, pero el usuario no ve la diferencia y tú no tienes incentivo para mitigar.
- Recomendación: cuentan, **pero** mides aparte un "SLI de éxito de Stripe" para tener visibilidad de cuánto de tu budget se va por culpa externa.

---

## Notas
TODO completa con tu razonamiento sobre los fallos externos. Esto es justo el tipo de decisión que el on-call y producto discuten una vez al trimestre.
