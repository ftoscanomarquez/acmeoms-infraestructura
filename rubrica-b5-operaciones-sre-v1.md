---
id: b5-operaciones-sre-v1
version: 1.0
language: es
sections:
  runbooks:
    title: "Runbooks completos"
    weight: 0.45
    source: repo
  prom_alerts:
    title: "Alertas PromQL"
    weight: 0.10
    source: repo
  postmortem_evolution:
    title: "Post-mortems con evolución V1 → V2 → V3"
    weight: 0.10
    source: repo
  slos_and_slis:
    title: "SLOs y SLIs"
    weight: 0.10
    source: repo
  error_budget_policy:
    title: "Política de error budget"
    weight: 0.05
    source: repo
  gameday_plan:
    title: "GameDay plan"
    weight: 0.10
    source: repo
  instrumentation:
    title: "Documento de instrumentación"
    weight: 0.05
    source: repo
  readme_decisions:
    title: "README + decisiones"
    weight: 0.05
    source: repo
rules:
  round: integer
---

# Rúbrica · Bloque 5 · Operaciones y SRE (AcmeOMS)

> Evalúa el "Trabajo final — Bloque 5 · Operaciones y SRE" del Máster en Ingeniería de Software. La rúbrica refleja los 8 criterios de la rúbrica de corrección del docente (45/10/10/10/5/10/5/5 pts) traducidos al formato data-driven del pipeline. Sin nota mínima — un trabajo apurado puede suspender (mediana esperada 70-80; >90 es referencia).

---

## Reglas generales

- **Notas enteras** (0-10), sin decimales.
- **Sin nota mínima** — la mediana esperada está alrededor de 70-80. Por debajo de 50, falta lectura crítica del enunciado.
- **Cada check vale 1 punto**; cada nivel tiene un máximo declarado.
- **Tres niveles** dentro de cada criterio:
  - **Base** — lo mínimo exigible que pide la rúbrica de corrección del docente para "Aprobado".
  - **Notable** — descriptor "Notable" del docente: trabajo sólido y publicable internamente.
  - **Excepcional** — descriptor "Excelente" del docente: referencia para próximas ediciones, o uno de los bonus opcionales.
- **Penalizaciones del enunciado** se modelan como checks Base positivos: si el alumno incumple ("reinicia el servicio" como única acción, SLO sobre infra, alerta sin `runbook_url`, política sin umbrales), pierde puntos en esa sección.

---

## Criterios y pesos (espejo de la rúbrica del docente)

| Criterio | Peso | Pts original | Lo que cubre |
|---|---|---|---|
| **Runbooks completos** | 45% | 45 (15×3) | 3 runbooks con 6 secciones obligatorias, comandos ejecutables, idempotencia, verificación medible |
| **Alertas PromQL** | 10% | 10 | `for:`, `severity`, annotations parametrizadas, `runbook_url` |
| **Post-mortems V1→V2→V3** | 10% | 10 | 3 versiones con evolución real, métricas comparativas, V3 automatizada |
| **SLOs y SLIs** | 10% | 10 | SLI en PromQL ejecutable, basado en experiencia de usuario, error budget en minutos/mes, burn rate |
| **Política de error budget** | 5% | 5 | Umbrales numéricos, feature freeze, excepción safety-fix, revisión periódica |
| **GameDay plan** | 10% | 10 | Hipótesis verificable, escenario con comando exacto, escape hatch numérico, roles |
| **Documento de instrumentación** | 5% | 5 | Tabla `quality attribute → métrica → SLI → alerta` para todos los módulos |
| **README + decisiones** | 5% | 5 | 3 trade-offs con justificación cuantitativa, mención de cambios IA |

**Nota final** = `0.45 × NotaRun + 0.10 × NotaAlt + 0.10 × NotaPM + 0.10 × NotaSLO + 0.05 × NotaEB + 0.10 × NotaGD + 0.05 × NotaIns + 0.05 × NotaRDM`

---

<!-- section: runbooks -->

## Runbooks completos (45%)

> Se evalúan 3 runbooks. El runbook obligatorio `db-pool-saturated` es bloqueante: sin él, el alumno tiene un techo del 50% en esta sección.

### Base — 1 pt cada uno (máx 5)
- [ ] `rb_obligatorio_presente` — Runbook obligatorio `db-pool-saturated` presente y completo (sin él, esta sección queda capada según penalización del docente).
- [ ] `rb_tres_runbooks_entregados` — Al menos 3 runbooks entregados (el obligatorio + 2 a elegir del catálogo).
- [ ] `rb_seis_secciones_obligatorias` — Cada runbook tiene las 6 secciones obligatorias: trigger, contexto, diagnóstico copiable, acciones idempotentes ordenadas, verificación medible, rollback.
- [ ] `rb_diagnostico_en_codigo` — Diagnósticos en bloques de código (no descripciones en prosa) — comandos copiables.
- [ ] `rb_no_solo_reiniciar` — Ningún runbook se limita a "reinicia el servicio" como única acción (penalización del docente: −20 pts si lo hace).

### Notable — 1 pt cada uno (máx 3)
- [ ] `rb_comandos_ejecutables_reales` — Comandos ejecutables tal cual: nombres reales de tablas/instancias/queues, no placeholders genéricos tipo `<INSTANCE_ID>` que requieran edición.
- [ ] `rb_acciones_ordenadas_por_impacto` — Acciones ordenadas explícitamente de menor a mayor impacto (escalado gradual, no "reinicia todo" como primer paso).
- [ ] `rb_verificacion_metrica_y_ventana` — Sección de verificación nombra una métrica concreta y una ventana de observación (ej. "latencia p95 < 200ms durante 5 min" — no "comprueba que va mejor").

### Excepcional — 1 pt cada uno (máx 2)
- [ ] `rb_automatizacion_de_uno` — Bonus +15 del docente: implementación automatizada de 1 runbook como script ejecutable, idempotente, con `--dry-run`, manejo de errores y logging.
- [ ] `rb_cuarto_runbook` — Bonus +5 del docente: 4º runbook adicional con el mismo nivel de detalle que los 3 obligatorios.

**Total máximo: 10 pts**

---

<!-- section: prom_alerts -->

## Alertas PromQL (10%)

> Cada runbook lleva su `alert.yaml`. Se evalúan los 3 conjuntamente.

### Base — 1 pt cada uno (máx 4)
- [ ] `pa_promql_valida` — Las 3 alertas tienen PromQL válida (paréntesis cerrados, labels existentes, sin errores de sintaxis).
- [ ] `pa_for_razonable` — Cada alerta tiene `for:` razonable: no 1s (false positives en cada blip), no 1h (llega tarde), algo en medio justificable.
- [ ] `pa_severity_consistente` — Cada alerta tiene `severity` declarada con valores consistentes entre las 3 (ej. critical/warning/info bien aplicados).
- [ ] `pa_runbook_url_en_todas` — Cada alerta tiene `runbook_url` enlazado a su runbook (penalización del docente: −10 pts si falta en alguna).

### Notable — 1 pt cada uno (máx 3)
- [ ] `pa_annotations_summary_description` — Cada alerta tiene `annotations` con `summary` y `description`.
- [ ] `pa_variables_parametrizadas` — Las annotations usan variables del incidente (`{{ $labels.X }}`, `{{ $value }}`) para hacer la alerta accionable.
- [ ] `pa_runbook_url_parametrizado` — El `runbook_url` lleva las variables ya pre-rellenadas (ej. `?service={{ $labels.service }}`).

### Excepcional — 1 pt cada uno (máx 3)
- [ ] `pa_burn_rate_en_al_menos_una` — Al menos una alerta usa burn rate del SLO en lugar de umbral plano.
- [ ] `pa_multiventana_burn_rate` — Burn rate con ventanas múltiples (corta + larga) para detectar quemado rápido y degradación sostenida.
- [ ] `pa_inhibition_o_grouping` — Reglas de `inhibition` o `grouping` configuradas en Alertmanager para evitar tormentas durante incidentes en cascada.

**Total máximo: 10 pts**

---

<!-- section: postmortem_evolution -->

## Post-mortems V1 → V2 → V3 (10%)

> Se evalúa el `post-mortems.md` del runbook obligatorio (define el estándar), más muestreo en los otros 2 runbooks.

### Base — 1 pt cada uno (máx 4)
- [ ] `pm_tres_versiones_presentes` — Tres versiones claramente diferenciadas (V1, V2, V3) — no 1-2 ni 4+.
- [ ] `pm_v1_mitigacion_manual` — V1 documenta mitigación manual con narrativa (cómo se resolvió el primer incidente sin runbook).
- [ ] `pm_v2_comandos_exactos` — V2 incluye comandos exactos y árbol de diagnóstico (lo que dio origen al runbook actual).
- [ ] `pm_v3_automatizacion_o_prevencion` — V3 incluye automatización preventiva (script, cron, hook) — no es V2 con palabras distintas.

### Notable — 1 pt cada uno (máx 3)
- [ ] `pm_narrativa_creible` — Cada versión tiene narrativa creíble: fecha del incidente, on-call, duración real, lo que se mejoró.
- [ ] `pm_tabla_metricas_comparativas` — Tabla de métricas mostrando reducción de tiempo de mitigación y toil entre V1, V2 y V3.
- [ ] `pm_aprendizaje_accionable` — Cada versión cierra con un aprendizaje accionable explícito (no "aprendimos mucho", sí "ahora añadimos burn-rate alert para detectar a los 5 min").

### Excepcional — 1 pt cada uno (máx 3)
- [ ] `pm_v3_con_script_real` — V3 incluye script o cron real (no pseudocódigo) — listo para desplegar.
- [ ] `pm_evolucion_otros_runbooks` — Los otros 2 runbooks también muestran evolución V1→V2→V3 con el mismo estándar (no solo el obligatorio).
- [ ] `pm_referencias_externas` — Los post-mortems referencian incidentes reales de la industria similar (ej. Cloudflare 2023, GitHub 2018) para contextualizar las decisiones.

**Total máximo: 10 pts**

---

<!-- section: slos_and_slis -->

## SLOs y SLIs (10%)

> Evaluar `slos/slos-orders.md` y `slos/slos-payments.md` conjuntamente.

### Base — 1 pt cada uno (máx 4)
- [ ] `slo_dos_slos_definidos` — Al menos 2 SLOs definidos (Orders + Payments).
- [ ] `slo_sli_promql_ejecutable` — Cada SLO tiene SLI con numerador / denominador / ventana, expresado en PromQL ejecutable.
- [ ] `slo_experiencia_usuario` — Los SLOs miden experiencia del usuario, no salud de infra (penalización del docente: −10 pts si un SLO mide CPU/RAM/uptime).
- [ ] `slo_error_budget_minutos_mes` — Error budget calculado en minutos al mes con la operación matemática explícita (no solo el porcentaje).

### Notable — 1 pt cada uno (máx 3)
- [ ] `slo_justificacion_basada_en_usuario` — Justificación basada en experiencia del usuario ("el cliente no completa la compra"), no en infra ("la VM está arriba").
- [ ] `slo_burn_rate_definido` — Burn rate definido con la fórmula correcta (orden de operadores correcto, ventanas en relación al budget).
- [ ] `slo_payments_discute_externos` — SLO de Payments discute razonadamente fallos externos (Stripe down → ¿cuenta contra mi error budget o lo excluimos? con criterio).

### Excepcional — 1 pt cada uno (máx 3)
- [ ] `slo_multi_window_alerting` — Burn rate con múltiples ventanas (1h fast burn + 6h slow burn) según las recomendaciones del SRE Workbook.
- [ ] `slo_dependency_aware` — SLOs distinguen "fallos del servicio" vs "fallos por dependencias upstream" con etiquetas (`reason="upstream"`).
- [ ] `slo_objetivo_por_segmento` — Objetivos diferenciados por segmento crítico (ej. checkout p99 más estricto que catálogo p99) con justificación.

**Total máximo: 10 pts**

---

<!-- section: error_budget_policy -->

## Política de error budget (5%)

### Base — 1 pt cada uno (máx 4)
- [ ] `eb_documento_existe` — Una página dedicada a política de error budget (no enterrada en SLOs).
- [ ] `eb_umbrales_numericos` — Niveles con umbrales numéricos exactos (no "verde = poco"; sí "verde = >50% budget restante"; penalización −5 si no los hay).
- [ ] `eb_cuatro_niveles_con_acciones` — Cuatro niveles (verde / amarillo / rojo / muy rojo) con consecuencias accionables por nivel.
- [ ] `eb_feature_freeze_explicito` — Política de feature freeze explícita en nivel rojo (% de capacidad dedicado a estabilizar).

### Notable — 1 pt cada uno (máx 3)
- [ ] `eb_excepcion_safety_fix` — Excepción safety-fix definida con quién la aprueba y bajo qué condiciones.
- [ ] `eb_revision_periodica` — Mecanismo de revisión trimestral (o periódica) de la política con responsable nombrado.
- [ ] `eb_comunicacion_al_equipo` — Define cómo se comunica el estado del budget al equipo (dashboard, channel, email semanal).

### Excepcional — 1 pt cada uno (máx 3)
- [ ] `eb_escenario_real` — Incluye un escenario real ("qué pasó en el sprint 23 cuando se agotó") con narrativa y lecciones aprendidas.
- [ ] `eb_dependencia_de_severidad` — Política distingue agotamiento por bugs internos vs incidentes externos con tratamiento distinto.
- [ ] `eb_metrica_de_efectividad` — Define cómo medir la efectividad de la política (ej. "tras 2 trimestres de feature freeze, MTTR bajó X%").

**Total máximo: 10 pts**

---

<!-- section: gameday_plan -->

## GameDay plan (10%)

### Base — 1 pt cada uno (máx 4)
- [ ] `gd_hipotesis_verificable` — Hipótesis explícita y verificable ("el failover de Cloud SQL completa en <60s" — no "ver cómo se comporta el sistema").
- [ ] `gd_escenario_comando_exacto` — Escenario concreto con comando exacto (`pumba kill ...`, `iptables -A ...`) — no "provocar caída de la BD".
- [ ] `gd_alcance_acotado` — Alcance acotado con sección "sí toca / no toca" innegociable (qué partes del sistema, qué tráfico, qué entorno).
- [ ] `gd_conecta_con_runbook` — El escenario conecta claramente con uno de los runbooks del propio alumno (no es ejercicio aislado).

### Notable — 1 pt cada uno (máx 3)
- [ ] `gd_metricas_baseline_esperado` — Tabla baseline / esperado / verificación con valores numéricos (no descripciones).
- [ ] `gd_escape_hatch_numerico` — Escape hatch con criterio numérico ("abort si error rate >5% durante 2 min" — no "abort si va mal").
- [ ] `gd_roles_asignados` — Roles asignados: Game Master, Observadores, On-call shadow, Comunicación.

### Excepcional — 1 pt cada uno (máx 3)
- [ ] `gd_segunda_iteracion_propuesta` — Segunda iteración propuesta para 3 meses después con criterio de mejora explícito.
- [ ] `gd_runbook_de_recuperacion` — Runbook de recuperación post-ejercicio incluido (qué hacer si algo queda en estado inconsistente).
- [ ] `gd_comunicacion_stakeholders` — Plan de comunicación a stakeholders no-técnicos (qué decir antes, durante, después).

**Total máximo: 10 pts**

---

<!-- section: instrumentation -->

## Documento de instrumentación (5%)

### Base — 1 pt cada uno (máx 4)
- [ ] `ins_doc_existe` — Documento de instrumentación entregado (`instrumentation.md` o similar).
- [ ] `ins_tabla_quality_attribute` — Tabla `quality attribute → métrica → SLI → alerta` presente.
- [ ] `ins_modulos_cubiertos` — Cubre al menos 4 módulos del OMS (Catalog, Inventory, Orders, Payments, Billing, IAM).
- [ ] `ins_relaciona_spec` — Las métricas se relacionan explícitamente con quality attributes de la spec del Bloque 1 (no métricas inventadas).

### Notable — 1 pt cada uno (máx 3)
- [ ] `ins_todos_los_modulos` — Cubre **todos** los módulos del OMS (6 módulos + infra compartida).
- [ ] `ins_logs_estructurados_schema` — Sección de logs estructurados con esquema JSON definido (campos obligatorios, niveles, correlación).
- [ ] `ins_use_y_red` — Distingue explícitamente métricas USE (Utilization / Saturation / Errors) y RED (Rate / Errors / Duration) por tipo de recurso.

### Excepcional — 1 pt cada uno (máx 3)
- [ ] `ins_dashboard_grafana_json` — Bonus +10 del docente: dashboard Grafana en JSON importable, funcional, con paneles para los SLOs y los runbooks del alumno.
- [ ] `ins_coste_telemetria` — Coste estimado de telemetría con cifras concretas (€/mes por módulo, tradeoff cardinality vs cost).
- [ ] `ins_retention_policy` — Política de retención por tipo de telemetría (métricas, logs, traces) con justificación coste/utilidad.

**Total máximo: 10 pts**

---

<!-- section: readme_decisions -->

## README + decisiones (5%)

### Base — 1 pt cada uno (máx 4)
- [ ] `rdm_existe` — `README.md` presente en la raíz del repo.
- [ ] `rdm_seccion_decisiones` — Sección "Decisiones" con al menos 3 trade-offs reales y específicos del trabajo.
- [ ] `rdm_decisiones_estructura` — Cada decisión tiene: contexto, opciones consideradas, decisión tomada, justificación.
- [ ] `rdm_cambios_ia_documentados` — Mención explícita de qué cambió del borrador de IA y por qué (política de uso de IA del enunciado).

### Notable — 1 pt cada uno (máx 3)
- [ ] `rdm_justificacion_cuantitativa` — Cada decisión incluye justificación cuantitativa (números, no opiniones — ej. "elegimos PromQL multi-window porque reduce falsos positivos del 8% al 1.2% según nuestro test").
- [ ] `rdm_instrucciones_verificacion_local` — Instrucciones para verificar el trabajo localmente (cómo ejecutar scripts, cómo simular alertas, dónde están los dashboards).
- [ ] `rdm_indice_navegacion` — Índice con enlaces a runbooks, post-mortems, SLOs, GameDay, instrumentación para navegación rápida.

### Excepcional — 1 pt cada uno (máx 3)
- [ ] `rdm_ethical_risk` — Bonus +10 del docente: ethical risk assessment con 5+ riesgos (severidad / probabilidad / control técnico / control organizativo / responsable / evidencia). Quality attributes derivados explícitos.
- [ ] `rdm_oncall_voz_alta` — Documenta que probó leer uno de sus runbooks en voz alta y modificó X y Y como resultado (bandera verde del docente).
- [ ] `rdm_runbook_propio_justificado` — Introduce un runbook propio que no está en el catálogo del docente y lo justifica como sustituto válido (bandera verde del docente).

**Total máximo: 10 pts**

---

## Antipatrones específicos que penalizan

> Estas son las **penalizaciones globales** de la rúbrica del docente (hasta −45 pts acumulables). En este formato data-driven se reflejan como checks Base concretos. Si los incumples, pierdes la nota Base de la sección afectada.

- **"Reinicia el servicio" como única acción de un runbook** (`rb_no_solo_reiniciar`): equivalente a −20 pts del docente.
- **SLO mide salud de infra en lugar de experiencia del usuario** (`slo_experiencia_usuario`): equivalente a −10 pts.
- **Alerta sin `runbook_url`** (`pa_runbook_url_en_todas`): equivalente a −10 pts.
- **Política de error budget sin umbrales numéricos** (`eb_umbrales_numericos`): equivalente a −5 pts.

## Banderas rojas (señales de trabajo apurado o IA sin revisar)

> Si el evaluador detecta alguna de estas señales, debe ser estricto con las secciones afectadas (descripción de banderas rojas del docente):

- Comandos genéricos del tipo `psql -c "SELECT * FROM ..."` sin nombres reales de tablas → rompe `rb_comandos_ejecutables_reales`.
- Frases textuales típicas de LLM ("Es importante destacar que…", "En conclusión…", "En el mundo dinámico de…") → rompe `rdm_cambios_ia_documentados`.
- Post-mortems en los que las 3 versiones son la misma con palabras distintas → rompe `pm_tres_versiones_presentes` o `pm_v3_automatizacion_o_prevencion`.
- SLOs medidos sobre métricas del sistema operativo (CPU, RAM) → rompe `slo_experiencia_usuario`.
- Alertas sin `for:` (disparan en cada blip) → rompe `pa_for_razonable`.
- GameDay plan que se ejecutaría en producción sin protección → rompe `gd_alcance_acotado` o `gd_escape_hatch_numerico`.

## Banderas verdes (señales de trabajo de referencia)

> Señales de trabajo en percentil 90+ que merecen destacarse. La rúbrica las premia con checks Excepcional:

- Runbook propio no del catálogo + justificación → `rdm_runbook_propio_justificado`.
- Política de error budget con escenario real del sprint → `eb_escenario_real`.
- GameDay con segunda iteración planificada → `gd_segunda_iteracion_propuesta`.
- Distinción USE vs RED en instrumentación → `ins_use_y_red`.
- Lectura en voz alta del runbook con cambios derivados → `rdm_oncall_voz_alta`.
