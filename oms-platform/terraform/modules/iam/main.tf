# ── Módulo: IAM ────────────────────────────────────────────────────
# Workload Identity Federation para que GitHub Actions despliegue
# SIN claves estáticas (Vídeo 4). Service Accounts con scope mínimo.

variable "project_id" { type = string }
variable "env" { type = string }
variable "github_repository" { type = string } # formato "owner/repo"
variable "cloud_run_sa" { type = string }      # email del SA del runtime
variable "labels" { type = map(string) }
# Ver comentario completo en terraform/variables.tf — vacío en staging,
# solo se usa en producción para el permiso cross-proyecto de `cosign copy`.
variable "staging_project_id" {
  type    = string
  default = ""
}

# ─── Workload Identity Pool ──────────────────────────────────────
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool-${var.env}"
  display_name              = "GitHub Actions — ${var.env}"
  description               = "Pool para que GHA impersone SAs sin claves estáticas."
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
    # HALLAZGO REAL (Fase 6, ver BITACORA-COMANDOS.md § 6.11): la nota
    # anterior en este bloque afirmaba que "sts.amazonaws.com" era el
    # audience por defecto de GitHub Actions y que funcionaba igual para
    # cualquier proveedor receptor — INCORRECTO en la práctica. La acción
    # oficial `google-github-actions/auth@v2` NO usa ese audience: genera
    # el token OIDC con audience = la URL COMPLETA de este mismo provider
    # (`https://iam.googleapis.com/projects/.../providers/github-provider`).
    # Con `allowed_audiences = ["sts.amazonaws.com"]` configurado, GCP
    # rechazaba la autenticación real con:
    #   "invalid_grant: The audience in ID Token [...] does not match
    #    the expected audience."
    # Se elimina `allowed_audiences` por completo: al omitirlo, Google usa
    # su propio default (la URL del provider), que es exactamente lo que
    # `google-github-actions/auth@v2` ya genera — sin necesidad de declarar
    # nada manualmente. "sts.amazonaws.com" es un valor real, pero solo
    # aplica cuando el cliente que arma el token lo pide explícitamente
    # (algunos ejemplos antiguos de terceros lo hacían); la acción oficial
    # de Google no lo hace.
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
  }

  # 🔒 Restricción CRÍTICA: solo workflows de este repo concreto
  # Y solo desde tags de release (refs/tags/v*).
  attribute_condition = <<-EOT
    assertion.repository == "${var.github_repository}" &&
    assertion.ref.startsWith("refs/tags/v")
  EOT
}

# ─── Service Account que asume el pipeline ────────────────────────
resource "google_service_account" "cicd" {
  account_id   = "oms-${var.env}-cicd"
  display_name = "OMS ${var.env} — CI/CD SA (impersonado vía WIF)"
}

# Permiso para que el pool impersone este SA (solo el repo correcto).
resource "google_service_account_iam_binding" "cicd_wif" {
  service_account_id = google_service_account.cicd.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}",
  ]
}

# ─── Permisos del SA de CI/CD (principio de mínimo privilegio) ──
# NOTA DE DISEÑO (agregado por el equipo): el pipeline (Fase 6) hace 3
# cosas en secuencia — (1) construir y subir la imagen Docker, (2)
# desplegar esa imagen en Cloud Run vía Ansible/gcloud, y (3) leer estado
# de Cloud Run para el traffic-splitting y la verificación post-deploy
# (comandos `gcloud run services describe` / `gcloud run revisions list`
# que ya usa el role oms_cloud_run de Ansible). Roles justificados:
#
#   - roles/run.developer            → desplegar y gestionar revisiones/
#                                       tráfico de Cloud Run (cubre además
#                                       la lectura de servicios/revisiones
#                                       que usa Ansible para comparar
#                                       imágenes y hacer el traffic-split).
#   - roles/artifactregistry.writer  → `docker push` de la imagen construida.
#   - roles/artifactregistry.reader  → agregado explícitamente en vez de
#                                       asumir que "writer" ya cubre
#                                       lectura: Cloud Run necesita poder
#                                       LEER la imagen del repositorio al
#                                       desplegar, y es más correcto (y
#                                       auditable) declarar cada permiso
#                                       que realmente se usa, en vez de
#                                       confiar en un rol más amplio.
#
# NUNCA roles/owner ni roles/editor — ninguno de los 3 pasos del pipeline
# necesita crear/modificar infraestructura (eso lo hace Terraform, con la
# autenticación humana del desarrollador, no el SA de CI/CD).
#
# HALLAZGO REAL (Fase 6, Trivy config — GCP-0011, MEDIUM): roles/iam.
# serviceAccountUser vivía en esta misma lista, otorgado con
# google_project_iam_member — es decir, a nivel de PROYECTO completo. Eso
# le daba al SA de CI/CD la capacidad de "actuar como" CUALQUIER Service
# Account del proyecto (incluidos, en teoría, otros SAs que se creen en el
# futuro), no solo el de runtime de Cloud Run que realmente necesita.
# Corregido: se movió a un binding sobre el RECURSO específico del SA de
# runtime (google_service_account_iam_member más abajo) — mismo patrón ya
# usado para el binding de WIF (google_service_account_iam_binding) y para
# los roles del propio SA de runtime, acotados a lo mínimo necesario.
locals {
  cicd_roles = [
    "roles/run.developer",
    "roles/artifactregistry.writer",
    "roles/artifactregistry.reader",
  ]
}

resource "google_project_iam_member" "cicd" {
  for_each = toset(local.cicd_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.cicd.email}"
}

# roles/iam.serviceAccountUser ACOTADO al SA de runtime concreto (no a nivel
# de proyecto) — necesario para que el SA de CI/CD pueda "actuar en nombre
# de" el SA de runtime al desplegar en Cloud Run (Cloud Run exige este
# permiso explícito, no basta con crear el recurso), pero sin extenderlo a
# ningún otro Service Account del proyecto.
resource "google_service_account_iam_member" "cicd_act_as_runtime" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${var.cloud_run_sa}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cicd.email}"
}

# HALLAZGO REAL (Fase 6, ver BITACORA-COMANDOS.md § 6.16): el pre_task de
# playbooks/deploy.yml (Fase 5) ejecuta `terraform init`/`terraform output`
# para leer cpu/memory/instancias como fuente de verdad — eso exige que el
# SA que corre Ansible pueda LEER el bucket de estado remoto de Terraform.
# Nunca se le había dado ese permiso: hasta la Fase 5, Terraform solo se
# ejecutaba con la cuenta humana del desarrollador (con permisos amplios de
# owner/editor a nivel de cuenta personal), nunca con el SA de CI/CD. Sin
# este binding, `terraform init -reconfigure` fallaba en el pipeline real:
#   "403: ...cicd@... does not have storage.objects.list access to the
#    Google Cloud Storage bucket ...-tfstate"
# Se otorga SOLO lectura (roles/storage.objectViewer), acotada al bucket
# específico de este entorno (no a todo el proyecto) — el pre_task únicamente
# LEE outputs, nunca aplica ni modifica el estado real.
resource "google_storage_bucket_iam_member" "cicd_tfstate_reader" {
  bucket = "${var.project_id}-tfstate"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.cicd.email}"
}

# HALLAZGO REAL (Fase 6, ver BITACORA-COMANDOS.md § 6.18): `cosign copy`
# (paso "Copiar la firma original al registro de producción" del workflow)
# necesita LEER del Artifact Registry de STAGING y ESCRIBIR en el de
# PRODUCCIÓN dentro de la misma llamada — pero el pipeline solo mantiene
# una identidad de GCP activa a la vez (o staging, o producción, nunca
# ambas simultáneamente). Falló con:
#   "DENIED: Permission 'artifactregistry.repositories.downloadArtifacts'
#    denied on resource '.../projects/acmeoms-staging-fatm/.../oms'"
# porque en el momento de `cosign copy`, la sesión activa ya era la de
# producción (re-autenticada en el paso anterior), sin ningún permiso
# sobre el proyecto de staging. Se resuelve dando al SA de CI/CD de
# PRODUCCIÓN un permiso de solo lectura, cross-proyecto, sobre el
# Artifact Registry de staging — el patrón real de "promoción entre
# entornos": el destino necesita permiso explícito para leer del origen.
# `count` lo condiciona a que exista `staging_project_id` (solo se pasa en
# production.tfvars); en staging, este recurso simplemente no se crea.
resource "google_project_iam_member" "cicd_read_staging_registry" {
  count   = var.staging_project_id != "" ? 1 : 0
  project = var.staging_project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.cicd.email}"
}

# ─── Permisos del SA del Cloud Run runtime ───────────────────────
# El runtime SOLO necesita leer secretos y conectar a Cloud SQL.
resource "google_project_iam_member" "runtime_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${var.cloud_run_sa}"
}

resource "google_project_iam_member" "runtime_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${var.cloud_run_sa}"
}

# ─── Outputs ──────────────────────────────────────────────────────
output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
  # Formato consumible por google-github-actions/auth:
  # projects/<NUM>/locations/global/workloadIdentityPools/<POOL>/providers/<PROVIDER>
}

output "cicd_service_account_email" {
  value = google_service_account.cicd.email
}
