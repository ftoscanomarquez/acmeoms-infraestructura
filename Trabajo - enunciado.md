# Trabajo final — Bloque 5 · Operación y observabilidad

## 1 · Contexto

En el Bloque 4 construiste la plataforma del OMS sobre GCP: VPC, Cloud SQL, Memorystore, Cloud Run, Load Balancer, CI/CD con WIF. **La plataforma corre**.

Lo que **no tienes** es ningún manual de operaciones, ni un SLO formal, ni una sola alerta configurada, ni un solo runbook escrito. Si algo se rompe en producción ahora mismo, el on-call empieza a improvisar a las 3 AM con un café y mucha esperanza.

Tu trabajo en el Bloque 5 es **cerrar ese gap**: entregar el conjunto de documentos operativos que convierten una plataforma "viva" en una plataforma "gobernable".

> 💡 Una observación honesta sobre este trabajo
> El entregable son **documentos**: runbooks, políticas, planes, mocks de YAML. Suena menos sexy que el Bloque 4 (donde escribías Terraform real). Pero en operación, el oficio se materializa en documentos. Un runbook bien escrito a las 3 AM vale más que mil dashboards bonitos. Este trabajo es el que separa a un equipo de ops maduro de uno que aguanta como puede.

---

## 2 · Objetivo

Producir un repositorio Git con la documentación operativa completa del OMS:

- **3 runbooks completos** (1 obligatorio + 2 a elegir del catálogo)
- Cada runbook con su **alerta PromQL**, **contexto operativo** y **evolución a lo largo de 3 post-mortems**
- **2 SLOs formales** con sus SLIs derivados de la spec
- **1 política de error budget** de una página
- **1 GameDay plan** que valida uno de tus runbooks
- **1 documento de instrumentación** que dice qué se monitoriza en cada módulo del OMS y por qué

Todo el trabajo aplica sobre la arquitectura del OMS (la del `03-arquitectura.md`). Donde necesites comandos concretos, puedes usar la demo `codecrypto-ai` del handoff como referencia.

---

## 3 · Restricciones de la spec que tienes que cumplir

### Heredadas del Bloque 4 (releídas con ojos de operación)
- **REG-GDPR-001** — Datos solo en regiones europeas
- **NFR-AVAIL-001** — Multi-AZ con failover automático (los SLOs deben reflejar esto)
- **NFR-PERF-002** — p95 < 250 ms en endpoints críticos
- **NFR-PERF-003** — p99 < 800 ms
- **OPS-005** — Backups con PITR 14d, RTO ≤ 4h
- **OPS-007** — Degradación elegante: si una pieza cae, el sistema sigue respondiendo

### Del oficio que aprendiste en este bloque

| # | Regla | Vídeo |
|---|---|---|
| 1 | Cada runbook tiene trigger · contexto · diagnóstico copiable · acciones idempotentes · verificación medible · rollback | V3 |
| 2 | Cero "reinicia el servicio" como única acción | V3 |
| 3 | Los post-mortems muestran evolución (V1 manual → V2 con comandos → V3 automatizada) | V3 + V5 |
| 4 | Los SLOs miden lo que importa al **usuario**, no lo que es fácil de medir | V2 |
| 5 | Toda alerta tiene `runbook_url` con variables del incidente pre-rellenadas | V1 + V3 |
| 6 | La política de error budget tiene umbrales **numéricos** y consecuencias **explícitas** | V2 |
| 7 | Cuando una acción de mitigación se puede expresar como feature flag, **se expresa** | V4 |

---

## 4 · Entregables

```
oms-operations/
├── README.md                              ← cómo arrancar
├── Trabajo - enunciado.md                 ← este documento (no se modifica)
├── .gitignore
│
├── runbooks/
│   ├── README.md                          ← índice + criterios comunes
│   ├── _template/
│   │   ├── runbook-template.md            ← copia y rellena para cada uno
│   │   ├── alert-template.yaml
│   │   └── post-mortems-template.md
│   │
│   ├── 01-db-pool-saturated/              ← OBLIGATORIO (todos)
│   │   ├── runbook.md
│   │   ├── alert.yaml
│   │   └── post-mortems.md
│   │
│   ├── 02-CHOOSE/                          ← elige 1 del catálogo abajo
│   └── 03-CHOOSE/                          ← elige otro distinto
│
├── slos/
│   ├── README.md
│   ├── slos-orders.md                      ← 1 SLO del módulo orders
│   ├── slos-payments.md                    ← 1 SLO del módulo payments
│   └── error-budget-policy.md              ← política 1 página
│
├── observability/
│   ├── README.md
│   └── instrumentation.md                  ← qué se instrumenta en cada módulo y por qué
│
├── gameday/
│   ├── README.md
│   └── gameday-plan.md                     ← diseñado para validar UNO de tus runbooks
│
└── ethics/                                 ← OPCIONAL (bonus)
    └── ethical-risk-assessment.md
```

### Catálogo de runbooks (elige 2 además del obligatorio)

| ID | Nombre | Dificultad | Aplica lo de |
|---|---|---|---|
| 01 | db-pool-saturated | Media | V1+V2+V3 — **OBLIGATORIO** |
| 02 | api-p95-high | Media | V1+V2+V3 |
| 03 | stripe-payment-gateway-degraded | Alta | V3+V4 (circuit breaker como mitigación) |
| 04 | outbox-backlog-creciente | Alta | V1+V3 (degradación silenciosa) |
| 05 | redis-cache-down | Media | V3 (degradación elegante) |
| 06 | cloud-sql-disk-full | Baja | V3 (prevención > reacción) |
| 07 | canary-rollout-failed | Media | V3+V4 (auto-rollback) |

---

## 5 · Rúbrica de evaluación (100 puntos)

| Bloque | Pts | Cómo se evalúa |
|---|---|---|
| **3 Runbooks completos** (15 pts × 3) | 45 | Estructura completa: trigger · contexto · diagnóstico copiable · acciones idempotentes ordenadas · verificación medible · rollback. Vale el `_template`. |
| **Alertas PromQL** | 10 | Reglas con `for:`, `severity`, annotations con `runbook_url` enlazada y variables del incidente pre-rellenadas. |
| **Post-mortems con evolución** | 10 | Cada runbook muestra V1 manual → V2 con comandos → V3 automatizada. Aprendizaje explícito por versión. |
| **SLOs y SLIs** | 10 | 2 SLOs definidos con SLI exacto (numerador / denominador / ventana), justificación basada en experiencia del usuario. |
| **Política de error budget** | 5 | Una página, niveles 🟢🟡🔴 con umbrales numéricos, política de freeze explícita. |
| **GameDay plan** | 10 | Hipótesis · escenario · alcance acotado · métricas a observar · escape hatch · roles. Conecta con uno de tus runbooks. |
| **Documento de instrumentación** | 5 | Tabla `quality attribute → métrica → SLI → alerta` para cada módulo del OMS. |
| **README + decisiones** | 5 | Sección "decisiones" con los 3 trade-offs principales que tomaste durante el trabajo. |

### Penalizaciones (acumulativas)
- −20 pts — si algún runbook tiene "reinicia el servicio" como única acción
- −10 pts — si un SLO mide salud de la infra en lugar de experiencia del usuario
- −10 pts — si las alertas no tienen `runbook_url` enlazado
- −5 pts — si la política de error budget no tiene umbrales numéricos

---

## 6 · Bonus opcionales

| Bonus | Pts | Qué implica |
|---|---|---|
| Ethical risk assessment | +10 | Para el "asistente IA de soporte al cliente" del OMS (sistema ficticio, ver `ethics/`), evaluación completa con 5 riesgos y controles |
| Implementación automatizada de 1 runbook | +15 | Script (bash o Python) idempotente con `--dry-run` que ejecuta uno de tus runbooks |
| Dashboard Grafana en JSON | +10 | Dashboard funcional con los paneles que apoyan tus runbooks y SLOs |
| 4º o 5º runbook adicional | +5 c/u | Cada runbook completo más allá de los 3 obligatorios, hasta 2 |

---

## 7 · Referencias del bloque

| Tarea | Vídeo |
|---|---|
| Diseñar alertas con burn rate y `runbook_url` | V1 + V2 |
| Definir SLOs/SLIs y política de error budget | V2 |
| Escribir un runbook efectivo (estructura, comandos, verificación) | V3 |
| Comunicar el post-mortem a stakeholders no técnicos | V3 |
| Acción de mitigación como feature flag o circuit breaker | V4 |
| Diseñar el GameDay plan | V5 |
| Ethical risk assessment | V5 (cierre) |

Y los temarios + guion del bloque:
- `Temario detallado – Módulo 2 · Operación, observabilidad y profesión.md`
- `Guion completo – Bloque 5 · Operación y observabilidad.md`

---

## 8 · Política de uso de IA

**Permitido y recomendado:** usar Claude, Copilot, Gemini o cualquier otro asistente para generar borradores.

**Obligatorio:** documentar en el README, en la sección "Decisiones", los **3 cambios concretos** que hiciste al borrador de la IA antes de aprobar el documento. Igual que vimos en el Vídeo 3 del Bloque 4 con el ejemplo de Cloud SQL.

Si tu runbook viene de un prompt y no lo has revisado críticamente, se nota en la primera lectura. Y a las 3 AM, en producción, **el runbook que generó la IA y nadie revisó es peor que no tener runbook**.

---

## 9 · Cómo entregar

1. Clona este esqueleto en un repo privado
2. Completa los `TODO` (búscalos con `grep -r TODO`)
3. Para cada runbook, **léelo en voz alta como si fueras el on-call a las 3 AM**: ¿podrías seguirlo sin pararte a pensar? Si no, falta detalle.
4. Comparte el repo con el correo del instructor
5. Tag de release `v1.0.0` apuntando al commit final

---

¡Adelante!
