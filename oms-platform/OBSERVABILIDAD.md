# OBSERVABILIDAD.md — Qué se loguea, qué se audita, cómo se detecta un problema

Este proyecto no implementa un stack de observabilidad completo (eso es explícitamente bonus — bastion + Datadog, Fase 7). Este documento describe lo que **sí** existe y funciona hoy contra GCP real, y qué haría falta para llegar al bonus.

## Logging de aplicación — Cloud Run

Cloud Run envía `stdout`/`stderr` del contenedor automáticamente a Cloud Logging, sin configuración adicional. `server.js` emite un log estructurado JSON mínimo al arrancar (`{"event": "server_started", "port": 8080}`) — suficiente para confirmar que el proceso realmente inició tras cada despliegue, sin necesitar acceso a la consola de Cloud Run.

## Logging de base de datos — Cloud SQL (`database_flags`)

Cloud SQL no da acceso al sistema de archivos del servidor (no hay `postgresql.conf` editable a mano) — la configuración de logging se hace vía `database_flags` en Terraform (`terraform/modules/database/main.tf`). 8 flags activos, cada uno con un propósito concreto:

| Flag | Valor | Por qué |
|---|---|---|
| `log_min_duration_statement` | `400` | Registra cualquier consulta que tarde más de 400ms — el mismo umbral que exige NFR-PERF-002 para `POST /api/orders` p95. Sin esto, sería imposible saber *qué* consulta concreta causa una latencia alta. |
| `log_statement` | `ddl` | Registra solo cambios de **estructura** (CREATE/ALTER/DROP), no datos de negocio — auditoría de cambios de esquema (REG-GDPR-003), sin inflar el volumen de logs con cada SELECT/INSERT normal. |
| `log_connections` | `on` | Trazabilidad de accesos (REG-GDPR-003). |
| `log_disconnections` | `on` | Complementa `log_connections` — permite calcular duración de sesión y detectar patrones anómalos de desconexión. |
| `log_lock_waits` | `on` | Indicador temprano de contención/deadlocks, señal de un posible vector de denegación de servicio antes de que degrade NFR-PERF-002. |
| `log_checkpoints` | `on` | Diagnóstico de rendimiento del propio motor (I/O pesado), no solo de las consultas de la app. |
| `log_temp_files` | `0` (todos) | Consultas que generan archivos temporales en disco suelen indicar un plan de ejecución ineficiente (falta de índice) — señal útil antes de que se traduzca en latencia visible. |

Nota sobre un aviso de Trivy (LOW, GCP-0021: "`log_statement` no debería estar activo"): deliberadamente **no** se cambia a `none`. Ese aviso genérico no distingue el matiz ya documentado — `ddl` registra solo cambios de esquema, nunca datos de negocio ni valores de columnas, así que no expone información sensible pese a estar activo. Se prioriza el valor de auditoría real sobre silenciar el aviso.

## Audit trail (REG-GDPR-003)

El enunciado exige "Cloud Logging con sink a un bucket de retención larga" para audit trail inmutable. **Estado real: no implementado en este trabajo** — es la pieza de observabilidad más grande que queda pendiente. Lo que sí cubre parcialmente ese requisito hoy:

- `log_connections`/`log_statement=ddl` en Cloud SQL (quién se conecta, qué cambios de esquema se hacen).
- Los logs de Cloud Run y del Load Balancer (`log_config { enable = true, sample_rate = 1.0 }` en `google_compute_backend_service`) ya llegan a Cloud Logging por defecto, con la retención por defecto de Cloud Logging (30 días) — no la retención larga e inmutable que pide REG-GDPR-003 explícitamente.

Para cerrar esto de verdad haría falta: un bucket de Cloud Storage con retención por política (`retention_policy` + `lock`, para inmutabilidad real) y un `google_logging_project_sink` que enrute los logs relevantes ahí. Ver `RETROSPECTIVA.md`.

## Healthchecks — cómo se detecta que algo está roto

Tres capas independientes, todas contra el mismo endpoint `/health` (nunca `/healthz` — ver hallazgo real más abajo):

1. **`HEALTHCHECK` de Docker** (`docker/Dockerfile`): `wget -qO- http://127.0.0.1:8080/health` cada 30s, 3 reintentos. Informativo a nivel de contenedor — Cloud Run no lo lee directamente, tiene su propio mecanismo (punto 2).
2. **Probes de Cloud Run** (`terraform/modules/compute/main.tf`): `startup_probe` (solo al arrancar, hasta ~35s de margen antes de darlo por fallido — evita mandar tráfico real a un contenedor que aún inicializa) y `liveness_probe` (continua durante toda la vida de la instancia; si falla 3 veces seguidas, Cloud Run **reinicia el contenedor automáticamente sin intervención humana** — el mecanismo técnico detrás de OPS-007, "el sistema degrada suavemente").
3. **Verificación post-deploy de Ansible** (`ansible/playbooks/deploy.yml`): `GET /health` con reintentos (6 intentos, 5s de espera) tras cada despliegue — confirma que el tráfico real, no solo la spec declarada, sirve una respuesta 200 válida.

### Hallazgo real: por qué el endpoint es `/health` y no `/healthz`

Durante el primer despliegue real (Fase 2), `/healthz` pasaba las probes *internas* de Cloud Run (el servicio llegaba a `status.conditions Ready=True`) pero el tráfico **público** externo a esa misma ruta devolvía un 404 genérico de Google, sin que la petición apareciera nunca en los logs de Cloud Run. Causa real: Google Front End (GFE) intercepta `/healthz` antes de que la petición llegue al contenedor, en algunos productos serverless de GCP — es una convención histórica interna reservada por Google, no un bug de este proyecto. Se estandarizó a `/health` en todo el código (`server.js`, `Dockerfile`, probes de Terraform, healthcheck de Ansible) para eliminar la ambigüedad.

## Degradación suave (OPS-007)

El enunciado exige que "si Redis cae, la app sigue respondiendo desde la DB". El placeholder actual (`server.js`) no implementa lógica de caché real (no hay código de negocio que cachear — ver la nota al inicio de ese archivo), así que este comportamiento **no está implementado ni probado**, solo diseñado a nivel de infraestructura: Redis y Cloud SQL son recursos independientes (`terraform/modules/database/main.tf`), sin ninguna dependencia dura entre ellos a nivel de infraestructura que forzara una caída en cascada. La responsabilidad de manejar un fallo de Redis con gracia (catch + fallback a la DB) es de la aplicación real, cuando exista.

## Firma y verificación de imágenes como observabilidad de la cadena de suministro

Cosign deja un registro público e inmutable en el *transparency log* de Rekor cada vez que se firma una imagen — es, en sí mismo, un mecanismo de auditoría: cualquiera puede verificar después qué workflow exacto (identidad OIDC) firmó qué digest exacto y cuándo, sin depender de los logs internos de GitHub Actions. Ver `CERTIFICADOS.md` para el detalle completo.

## SonarCloud — cableado, deliberadamente apagado

`.github/workflows/ci-cd.yml` incluye un paso real y funcional de SonarCloud (`SonarSource/sonarqube-scan-action@v4`), condicionado a `if: vars.SONAR_HOST_URL != ''`. Con esa variable sin definir (estado real de este proyecto), el paso aparece en el log de Actions como `skipped`, no se omite del YAML ni rompe el pipeline. Se dejó así a propósito, no por descuido: (1) `server.js` es un placeholder mínimo de infraestructura — no hay código de negocio real que un análisis estático de calidad tenga sentido de auditar todavía; (2) activarlo de verdad requiere una cuenta de SonarCloud, un `SONAR_TOKEN` (Secret, a diferencia de los identificadores de WIF que sí son Variables públicas) y un `sonar-project.properties`, ninguno de los cuales se justifica crear para un placeholder. Queda visible como capacidad ya integrada, lista para activar en el bloque que implemente el OMS real.

## Qué falta para observabilidad completa (bonus, Fase 7)

- Bastion VM con el agente de Datadog vía rol de Ansible, descubierta por inventario dinámico (`ansible/inventory/gcp.yml`, label `role=bastion`).
- Sink de Cloud Logging a un bucket con retención inmutable (audit trail real, REG-GDPR-003).
- Alertas reales sobre los healthchecks fallando o el `log_min_duration_statement` disparándose con frecuencia.
