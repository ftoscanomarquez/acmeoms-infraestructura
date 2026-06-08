# OMS Operations — Trabajo final Bloque 5

Esqueleto del trabajo final del **Bloque 5 · Operación y observabilidad**.
El enunciado completo está en `Trabajo - enunciado.md`.

## Estructura

```
oms-operations/
├── runbooks/        ← 3 runbooks (1 obligatorio + 2 a elegir)
├── slos/            ← 2 SLOs + política de error budget
├── observability/   ← plan de instrumentación
├── gameday/         ← 1 plan de GameDay
└── ethics/          ← OPCIONAL (bonus)
```

## Cómo arrancar

1. **Lee el enunciado** completo (`Trabajo - enunciado.md`).
2. **Empieza por la instrumentación** — necesitas tener claro qué medirías antes de poder definir SLOs y alertas:
   ```bash
   ${EDITOR:-vim} observability/instrumentation.md
   ```
3. **Define los SLOs** — la base de las alertas:
   ```bash
   ${EDITOR:-vim} slos/slos-orders.md slos/slos-payments.md slos/error-budget-policy.md
   ```
4. **Escribe el runbook obligatorio** primero, usando el template:
   ```bash
   ${EDITOR:-vim} runbooks/01-db-pool-saturated/runbook.md
   ${EDITOR:-vim} runbooks/01-db-pool-saturated/alert.yaml
   ${EDITOR:-vim} runbooks/01-db-pool-saturated/post-mortems.md
   ```
5. **Elige 2 runbooks más** del catálogo (ver enunciado §4):
   ```bash
   cp -r runbooks/_template runbooks/02-tu-eleccion-1
   cp -r runbooks/_template runbooks/03-tu-eleccion-2
   # luego renombra los ficheros y rellena los TODOs
   ```
6. **Diseña el GameDay** que valida uno de tus runbooks:
   ```bash
   ${EDITOR:-vim} gameday/gameday-plan.md
   ```
7. **(Bonus)** completa el `ethics/ethical-risk-assessment.md`.

## Verificación antes de entregar

```bash
# Todos los TODO rellenados
grep -r "TODO" . | grep -v node_modules | wc -l    # idealmente 0 (algunos opcionales pueden quedar)

# Cada runbook tiene los 3 ficheros mínimos
for d in runbooks/0*/; do
  for f in runbook.md alert.yaml post-mortems.md; do
    [ -f "$d/$f" ] && echo "✓ $d/$f" || echo "✗ FALTA $d/$f"
  done
done

# Cada alerta tiene runbook_url
grep -L "runbook_url" runbooks/*/alert.yaml    # idealmente vacío

# Cada SLO usa good/valid events (no salud de infra)
grep -L "good\|valid" slos/slos-*.md           # idealmente vacío
```

## Decisiones (rellénalo tú al final)

Sección obligatoria con los **3 trade-offs principales** que tomaste durante el trabajo. Ejemplos del tipo de decisión que esperamos ver documentada:

- "Definí el SLO de orders al 99,5% y no al 99,9% porque..."
- "Para el runbook X, ordené las acciones poniendo Y antes que Z porque..."
- "Borré las 5 líneas del borrador inicial que generó la IA porque..."

## Si te bloqueas

- Vuelve al vídeo correspondiente (mapeo en `Trabajo - enunciado.md` §7)
- Canal Slack `#trabajo-bloque-5`
- Lee tus runbooks en voz alta como si fueras el on-call a las 3 AM
