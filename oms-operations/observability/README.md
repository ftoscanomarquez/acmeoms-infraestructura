# Observability

> Plan de instrumentación: qué se monitoriza en cada módulo del OMS y por qué.

## Fichero

| Fichero | Qué contiene |
|---|---|
| `instrumentation.md` | Tabla `quality attribute → métrica → SLI → alerta` por cada módulo |

## Regla del oficio

Cada métrica que existe en tu sistema debe poder defenderse así:
> "Esta métrica existe porque la spec dice X, y la usamos para verificar Y."

Si no puedes responder esa frase, **no instrumentes esa métrica**. La telemetría tiene coste, y el ruido entierra la señal.
