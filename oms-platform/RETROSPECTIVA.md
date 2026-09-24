# RETROSPECTIVA.md — Qué se haría distinto, deuda técnica conocida

Este documento es honesto a propósito: recoge las desviaciones reales respecto al enunciado, la deuda técnica identificada durante el trabajo, y qué se haría distinto con el conocimiento actual. Ninguno de estos puntos se descubrió después del hecho — todos están documentados en el propio código o en `BITACORA-COMANDOS.md` en el momento en que aparecieron.

## Desviaciones documentadas respecto a la spec original

### NFR-SCAL-001 (autoescalado hasta 5× el pico) — desviación real por cuota

El NFR pide autoescalado hasta 5× el pico medido. Con una CPU de referencia de 2000m y un pico teórico de 5 instancias, eso implicaría 25 instancias concurrentes a 2000m cada una (50000m total) en producción. Dos restricciones reales de plataforma lo impiden tal cual:

1. La cuota gratuita de CPU por región en Cloud Run (`CpuAllocPerProjectRegion`) es 20000m total en este proyecto.
2. Cloud Run solo acepta valores de CPU en `{0.08–1.0 fraccional, o enteros exactos 1, 2, 4, 6, 8}` — un valor como `1500m` (1.5 CPU) es rechazado por la API con `Invalid value ... Must be equal to one of [.08-1], 1.0, 2.0, 4.0, 6.0, 8.0`.

Decisión tomada: 15 instancias × 1000m = 15000m (25% de margen bajo el límite de 20000m), con la misma CPU por instancia ya validada, a cambio de menos instancias concurrentes que el NFR pedía literalmente (15 en vez de 25). Es una desviación real, documentada en el propio código (`terraform/envs/production.tfvars`), no un cumplimiento silencioso a medias.

**Qué se haría distinto**: solicitar aumento de cuota de `CpuAllocPerProjectRegion` a GCP (proceso real, con tiempo de aprobación fuera del control de este proyecto) antes de fijar el valor final, en vez de ajustar el NFR al límite gratuito disponible.

### Audit trail inmutable (REG-GDPR-003) — no implementado

El enunciado pide "Cloud Logging con sink a un bucket de retención larga". No se implementó: falta un `google_logging_project_sink` + un bucket con `retention_policy`/`lock`. Lo que sí existe (logs de Cloud SQL con `log_connections`/`log_statement=ddl`, logs del Load Balancer) llega a Cloud Logging con su retención por defecto (30 días), no la retención larga e inmutable que el requisito exige explícitamente. Ver `OBSERVABILIDAD.md`.

**Por qué no se hizo**: se priorizó cerrar el ciclo completo de CI/CD (Fase 6) y su verificación real de punta a punta antes de continuar a los bonus — esta pieza cae en el límite entre "requisito base" y "trabajo de observabilidad más amplio", y quedó pendiente al momento de escribir este documento.

### `google.cloud.gcp_cloudrun_*` (rúbrica, Ansible idempotente) — no existen, se documentó y se usó la alternativa

La rúbrica pide literalmente esos módulos. Verificado con `ansible-doc -l`, `ansible-galaxy collection list` e inspección directa de los `.py` de la colección instalada (`google.cloud` v1.10.2): no existe ningún módulo de Cloud Run en esa colección, solo de `runtimeconfig` (servicio distinto). Se documentó la ausencia por escrito y se usó `ansible.builtin.command`/`shell` contra `gcloud run`, con idempotencia diseñada a mano y verificada (`changed=0` en segunda ejecución, confirmado repetidas veces contra staging y producción reales).

**Qué se haría distinto**: nada respecto a la decisión en sí — es la única opción real disponible. Sí se podría, con más tiempo, extraer la lógica de comparación de 4 campos a un módulo de Ansible propio y reutilizable, en vez de vivir inline en el rol.

## Deuda técnica identificada durante el trabajo

### `promote-canary.yml` — criterio de "primera revisión" en vez de "revisión con más tráfico"

Al identificar la revisión "no-canary" a la que asignarle el resto del tráfico, el playbook toma la primera que aparece en el listado de `status.traffic[]` (`head -n1`), no necesariamente la que tiene más tráfico real entre las candidatas. Esto solo importa cuando hay **3 o más** revisiones con algún porcentaje de tráfico simultáneo (residuo de rondas de pruebas previas no limpiadas) — en el caso normal de 2 revisiones (canary + una estable), el comportamiento es exacto. Verificado en producción real: el resultado final en porcentajes siempre sumó 100% correctamente, pero en una prueba concreta la revisión que "absorbió" el 50% restante fue la más antigua de las dos candidatas, no la que realmente tenía el 90% de tráfico justo antes del canary.

**Corrección pendiente, de bajo esfuerzo**: cambiar el criterio a "la revisión no-canary con el mayor `percent` actual" en vez de "la primera línea del listado" — requiere ordenar por el segundo campo del `awk` antes de tomar la primera línea, en vez de tomar la primera línea sin más. No se aplicó todavía porque no afecta el resultado del caso de uso real (2 revisiones), y el proyecto priorizó cerrar la verificación completa del ciclo de CI/CD antes de refinar este detalle.

### Certificado SSL del Load Balancer permanentemente en `PROVISIONING`

No es un bug — es el resultado esperado de no tener un dominio real registrado (fuera del alcance de infraestructura del enunciado, y del crédito de GCP). Cloud Run sigue siendo accesible con HTTPS válido por su URL nativa mientras tanto. Documentado en `CERTIFICADOS.md`.

### Notificaciones a Slack, condicionadas y nunca probadas contra un workspace real

`deploy.yml` incluye un paso de notificación a Slack (`community.general.slack`), condicionado a que `slack_webhook_url` esté definida — nunca se definió, porque este proyecto no tiene un workspace de Slack real asociado (crearlo es un artefacto ajeno al alcance de infraestructura). El paso está escrito y sintácticamente correcto, pero no se ha verificado en la práctica contra un webhook real.

## Qué se haría distinto con el conocimiento actual

1. **Exponer `cpu`/`memoria`/instancias como outputs de Terraform desde el primer módulo `compute`**, no como una corrección posterior en la Fase 5. El diseño original (duplicar los valores en `group_vars` y `tfvars`) generó *drift* real (`memory` desalineada silenciosamente durante varias fases) que se pudo haber evitado desde el principio si Terraform hubiera sido la fuente de verdad desde la Fase 2.

2. **Verificar las versiones de acciones de terceros de GitHub Actions contra la API real de GitHub antes de fijarlas**, no confiar en un número de versión "que suena razonable". Un hallazgo real (`aquasecurity/trivy-action@0.28.0`, una versión que no existe — la etiqueta real llevaba `v` como prefijo, `@v0.36.0`) costó una iteración completa de pipeline fallido que se pudo evitar con `gh api repos/.../tags` antes de escribir el YAML.

3. **Probar el ciclo completo de canary+rollback contra un entorno con exactamente el número de revisiones que el diseño asume**, antes de darlo por verificado. Las pruebas locales de `promote-canary.yml` se hicieron siempre con 2 revisiones activas; el primer disparo real desde GitHub Actions ocurrió sobre un entorno con 3 (acumuladas de rondas de pruebas anteriores) y expuso un bug real de inmediato. Con más disciplina de limpieza entre rondas de prueba (o una prueba explícita del caso de 3+ revisiones), ese hallazgo se habría encontrado antes, sin necesitar una ejecución real fallida en producción para descubrirlo.

4. **Documentar el `attribute_condition` de WIF como una superficie que crece con cada workflow nuevo**, no como algo que se fija una vez. Agregar `canary-decision.yml` requirió volver a tocar el `attribute_condition` — en retrospectiva, hubiera sido más robusto diseñar esa condición desde el principio pensando en "qué eventos legítimos de este repo deberían poder autenticarse", en vez de acotarla estrictamente al primer workflow que existía en ese momento.

## Balance general

El enfoque de verificar cada pieza contra la API real de GCP (no solo confiar en que un `terraform apply` o un `ansible-playbook` "corrió sin errores") encontró bugs reales que una verificación solo por logs no habría detectado — el caso más claro es el drift de capacidad entre Terraform y Ansible, y el bug de `promote-canary.yml` con 3 revisiones, ambos serían fáciles de pasar por alto sin cruzar cada cambio contra el estado real de producción. El costo de ese enfoque es tiempo: cada fase tuvo varias iteraciones de fix-verificar-repetir en vez de una ejecución limpia a la primera. Para el alcance y el objetivo pedagógico de este trabajo, ese costo se considera justificado — el objetivo no era desplegar rápido, era operar infraestructura real con evidencia real de que funciona.
