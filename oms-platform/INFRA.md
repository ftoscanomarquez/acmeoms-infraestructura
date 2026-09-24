# INFRA.md — Arquitectura real desplegada

Este documento describe la infraestructura **tal como quedó realmente aplicada** en GCP (`terraform apply` real contra `acmeoms-staging-fatm` y `acmeoms-production-fatm`), módulo por módulo, con los valores reales y las decisiones de diseño que llevaron a cada recurso. Para el flujo de diagramas visuales, ver [`DIAGRAMAS.md`](DIAGRAMAS.md); para cómo se despliega sobre esta base, ver [`DEPLOYMENT.md`](DEPLOYMENT.md).

## Vista general

```
                    Internet
                       │ HTTPS (443, cert managed por Google)
                       ▼
          ┌─────────────────────────────┐
          │  Global HTTPS Load Balancer │  google_compute_global_forwarding_rule
          │        + Cloud CDN          │  google_compute_backend_service (enable_cdn=true)
          └──────────────┬───────────────┘
                          │ Serverless NEG
                          ▼
          ┌─────────────────────────────┐
          │      Cloud Run: oms-<env>   │  google_cloud_run_v2_service
          │  (min/max instances, cpu,   │  imagen por DIGEST (nunca tag mutable)
          │   memoria — desde tfvars)   │
          └──────┬─────────────┬────────┘
                 │ socket      │ VPC Access Connector (/28)
                 ▼             ▼
       ┌──────────────┐  ┌─────────────────┐
       │  Cloud SQL   │  │ Memorystore     │
       │  PostgreSQL  │  │ Redis STANDARD_HA│
       │  REGIONAL HA │  │  (TLS + AUTH)    │
       └──────────────┘  └─────────────────┘
                 VPC privada (10.20.0.0/16) — europe-west3
                 Cloud NAT para salida (nada tiene IP pública)
```

## Módulo `network`

Una VPC en modo custom (`auto_create_subnetworks = false`) por entorno, región `europe-west3` (Frankfurt, REG-GDPR-001).

- **Subred `private`** (`10.20.0.0/20`): aloja Cloud SQL y Memorystore vía IP privada.
- **Subred `connector`** (`10.20.16.0/28`): dedicada al VPC Access Connector. El tamaño `/28` no es una elección — es un **requisito técnico duro** de GCP para este tipo de recurso (`google_vpc_access_connector`); un `/20` fue rechazado en la práctica con `Subnets used for VPC connectors must have a netmask of 28`.

**Nota de diseño real** sobre "subredes en al menos 2 zonas" (rúbrica, 25 pts): en GCP una subred no está atada a una zona — abarca automáticamente todas las zonas de su región (a diferencia de AWS). El requisito de NFR-AVAIL-001 se cubre con `availability_type = "REGIONAL"` en Cloud SQL (que sí reparte réplicas entre zonas), no con subredes duplicadas por zona. La segunda subred de este módulo existe por **segmentación funcional** (separar el tráfico del connector), no por redundancia de zona.

- **Cloud NAT** (`google_compute_router` + `google_compute_router_nat`, `AUTO_ONLY`): ningún recurso de este proyecto tiene IP pública; el NAT es la única vía de salida a internet para tráfico saliente (ej. una futura llamada a una API externa).
- **3 reglas de firewall explícitas** sobre una VPC que ya deniega todo por defecto:
  1. `allow-internal` — tráfico TCP/UDP/ICMP dentro de la propia VPC (`10.20.0.0/16`).
  2. `allow-iap-ssh` — SSH solo desde el rango oficial de Identity-Aware Proxy (`35.235.240.0/20`), acotado a VMs con `target_tags = ["iap-ssh"]`. No afecta a ningún recurso hoy — preparada para el bastion del bonus (Fase 7).
  3. `allow-lb-health-checks` — puerto 8080 solo desde los rangos oficiales de Google Front End (`130.211.0.0/22`, `35.191.0.0/16`), sin los cuales el Load Balancer marcaría el servicio como caído.

## Módulo `database`

- **Cloud SQL PostgreSQL 16**, `availability_type = "REGIONAL"` (NFR-AVAIL-001, failover automático multi-zona), `tier` distinto por entorno (`db-custom-2-7680` en staging, `db-custom-4-15360` en producción), `disk_type = PD_SSD` con autoresize.
- **Backups**: `point_in_time_recovery_enabled = true`, `transaction_log_retention_days = 7`, `retained_backups = 14` (OPS-005: PITR 14 días).
- **`ssl_mode = "ENCRYPTED_ONLY"`**: agregado tras un hallazgo real de Trivy (HIGH) — sin este campo, Cloud SQL admite conexiones sin cifrar incluso dentro de la red privada.
- **8 `database_flags` de logging**: `log_min_duration_statement=400` (mismo umbral que NFR-PERF-002 exige para p95), `log_statement=ddl` (auditoría de cambios de esquema, REG-GDPR-003), `log_connections`, `log_disconnections`, `log_lock_waits`, `log_checkpoints`, `log_temp_files=0` — los últimos 4 agregados tras hallazgos MEDIUM de Trivy.
- **Password**: generada con `random_password` (32 caracteres, conjunto de especiales acotado a uno seguro para Postgres), guardada en Secret Manager (`google_secret_manager_secret` + `_version`) — nunca aparece como texto literal en el código ni en el historial de git.
- **`deletion_protection = true`** + `lifecycle { prevent_destroy = true }` — doble defensa contra un `terraform destroy` accidental.
- **Memorystore Redis** `STANDARD_HA` (réplica automática), `REDIS_7_2`, `transit_encryption_mode = SERVER_AUTHENTICATION`, `auth_enabled = true`. `memory_size_gb`: 5 en producción, 1 en staging.
- **`depends_on` explícito** hacia la conexión de peering del módulo `network`: sin él, Terraform intentaba crear Cloud SQL/Redis en paralelo con esa conexión (ningún argumento las referencia directamente) y fallaba con `network doesn't have at least 1 private services connection`.

## Módulo `compute`

- **Artifact Registry** (`oms`, formato `DOCKER`) declarado en Terraform — se había creado inicialmente a mano con `gcloud artifacts repositories create` y se revirtió: fuera de Terraform, un futuro `destroy` lo dejaría huérfano generando coste indefinido.
- **Service Account de runtime** dedicada (`oms-<env>-runtime`), sin permisos amplios — solo lo que el módulo `iam` le otorga explícitamente (`cloudsql.client`, `secretmanager.secretAccessor`).
- **VPC Access Connector** (`min_instances=2`, `max_instances=3`) sobre la subred `connector` — puente entre Cloud Run (que vive fuera de la VPC por defecto) y Memorystore (IP privada, sin acceso público).
- **Cloud Run v2** (`google_cloud_run_v2_service`):
  - Imagen referenciada **por digest** (`image_repo@image_sha`), nunca por tag mutable — garantiza que el mismo binario corre en ambos entornos.
  - `cpu`/`memory`/`min_instances`/`max_instances` parametrizados desde `terraform/envs/<env>.tfvars` — única fuente de verdad, ver decisión #2 del README.
  - Conexión a Cloud SQL vía **socket** (`volumes { cloud_sql_instance {...} }`), no por IP — no requiere exponer la base de datos.
  - `startup_probe` (arranque, hasta ~35s de margen) y `liveness_probe` (continua, reinicia el contenedor si falla 3 veces seguidas — mecanismo técnico detrás de OPS-007) contra `/health`, **no** `/healthz` — hallazgo real: Google Front End intercepta `/healthz` en Cloud Run antes de llegar al contenedor, devolviendo 404 sin que la petición aparezca en logs.
  - `lifecycle.ignore_changes` sobre `image`, `traffic`, `client`, `client_version`, `template[0].revision` — Terraform declara la **forma inicial** del servicio; el control fino de qué imagen corre y cómo se reparte el tráfico pasa a ser responsabilidad exclusiva de Ansible desde el primer despliegue.
  - `roles/run.invoker` a `allUsers` — necesario para que Cloud Run acepte tráfico público real (llega vía el Load Balancer, no directo); sin este binding, la política IAM nace vacía y el servicio devuelve 403/404 aunque esté sano.
- **Load Balancer + Cloud CDN**: NEG serverless → Backend Service (`enable_cdn=true`, `cache_mode=CACHE_ALL_STATIC`, TTLs 3600/86400s) → URL map → Target HTTPS Proxy → Global Forwarding Rule (puerto 443). Certificado SSL **managed** por Google (`google_compute_managed_ssl_certificate`) — requiere un dominio real con registro DNS tipo A hacia la IP del LB; mientras no exista, el certificado queda en `PROVISIONING` sin bloquear el resto (Cloud Run sigue siendo accesible por su URL nativa con HTTPS ya válido). Ver `CERTIFICADOS.md`.

## Módulo `iam`

- **Workload Identity Federation**: un pool + provider OIDC por entorno (`github-pool-<env>`), sin ninguna clave estática de Service Account. `issuer_uri = "https://token.actions.githubusercontent.com"`.
- **`attribute_condition` real** (la verdadera barrera de seguridad, no el YAML del workflow):
  ```
  assertion.repository == "<owner>/<repo>" &&
  (
    assertion.ref.startsWith("refs/tags/v") ||
    (assertion.event_name == "workflow_dispatch" && assertion.ref == "refs/heads/main")
  )
  ```
  Acepta solo tags de release reales (dispara `ci-cd.yml`) o `workflow_dispatch` sobre `main` (dispara `canary-decision.yml`) — nunca cualquier rama o fork.
- **Service Account de CI/CD** (`oms-<env>-cicd`) con permisos acotados al mínimo necesario para 3 pasos: construir/subir imagen, desplegar en Cloud Run, y leer estado para el traffic-splitting:
  - `roles/run.developer`, `roles/artifactregistry.writer`, `roles/artifactregistry.reader` (a nivel de proyecto).
  - `roles/iam.serviceAccountUser` **acotado al recurso específico** del SA de runtime (`google_service_account_iam_member`), no a nivel de proyecto completo — corregido tras un hallazgo MEDIUM de Trivy que lo tenía sobre-otorgado.
  - `roles/storage.objectViewer` sobre el bucket de tfstate del propio entorno — necesario porque `deploy.yml` lee `terraform output -json`.
  - (Solo producción) `roles/artifactregistry.reader` cross-proyecto sobre el registro de **staging** — necesario para que `cosign copy` pueda leer la firma original al promocionar la imagen.
  - Nunca `roles/owner` ni `roles/editor` — ningún paso del pipeline crea o modifica infraestructura; eso lo hace Terraform con la cuenta humana del desarrollador.

## Diferencias reales entre staging y producción

Verificable con `diff terraform/envs/staging.tfvars terraform/envs/production.tfvars` y `diff ansible/group_vars/staging.yml ansible/group_vars/production.yml`. Cada línea es defendible en una frase:

| Diferencia | Staging | Producción | Por qué |
|---|---|---|---|
| `project_id` | `acmeoms-staging-fatm` | `acmeoms-production-fatm` | Proyectos GCP distintos (aislamiento total) |
| `db_tier` | `db-custom-2-7680` (2 vCPU/7.5GB) | `db-custom-4-15360` (4 vCPU/15GB) | Capacidad — tráfico real esperado |
| `cloud_run_min_instances` | `0` | `2` | Staging escala a cero (ahorro); producción nunca a cero (latencia consistente) |
| `cloud_run_max_instances` | `5` | `15` | Techo conservador en staging vs NFR-SCAL-001 en producción (ver `RETROSPECTIVA.md` sobre la desviación real de este NFR) |
| `traffic_percent` (Ansible) | `100` | `10` | Staging es *big-bang* (riesgo aceptado en QA); producción es canary progresivo |
| `staging_project_id` (IAM) | `""` (no aplica) | `acmeoms-staging-fatm` | Permiso cross-proyecto real para `cosign copy` — excepción documentada a la regla anterior, no una diferencia de capacidad |

Ninguna otra línea difiere — mismo `region`, mismo `vpc_cidr`, mismo `cloud_run_cpu`/`cloud_run_memory`, mismo `github_repository`, y el `image_sha` es (por diseño) el mismo digest exacto una vez promocionado.

## Recursos por módulo (resumen)

| Módulo | Recursos principales |
|---|---|
| `network` | 1 VPC, 2 subredes, 1 IP global de peering, 1 conexión de peering, 1 router + NAT, 3 firewalls |
| `database` | 1 instancia Cloud SQL, 1 base de datos, 1 usuario, 1 secreto + versión, 1 instancia Redis |
| `compute` | 1 repo Artifact Registry, 1 SA runtime, 1 VPC connector, 1 Cloud Run v2, 1 binding IAM público, 1 NEG, 1 backend service, 1 url map, 1 certificado, 1 proxy HTTPS, 1 IP global, 1 forwarding rule |
| `iam` | 1 WIF pool + provider, 1 SA CI/CD, bindings de WIF/roles (por entorno) |

Total verificado con `terraform apply` real: 38 recursos en la primera aplicación completa (Fases 0–2), más los agregados en fases posteriores (Secret Manager, permisos cross-proyecto, flags de logging).
