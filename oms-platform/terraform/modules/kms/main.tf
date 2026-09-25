# ── Módulo: KMS ────────────────────────────────────────────────────
# BONUS del enunciado (sección 6): "CMEK propia — Clave KMS gestionada
# por ti en lugar de la default de Google, aplicada a Cloud SQL y a un
# bucket."
#
# NOTA DE DISEÑO (agregado por el equipo, Fase 7): sin este módulo, todo
# el cifrado en reposo de este proyecto (Cloud SQL, Secret Manager, el
# propio tfstate en GCS) ya usa AES-256 con claves gestionadas por
# Google — cumple NFR-SEC-001 tal como está escrito ("Encriptación en
# reposo... AES-256 por defecto obligatorio"), CMEK es explícitamente
# el nivel opcional/bonus por encima de eso. La diferencia real: con
# CMEK, ESTE proyecto controla el ciclo de vida de la clave (rotación,
# revocación, auditoría de uso vía Cloud KMS) en vez de delegarlo
# completamente a Google — relevante si REG-GDPR-001/003 exigieran algún
# día demostrar control explícito sobre las claves de cifrado, no solo
# que el cifrado exista.

variable "project_id" { type = string }
variable "region" { type = string }
variable "env" { type = string }
variable "labels" { type = map(string) }

# ─── Keyring — el "directorio" que agrupa las claves de este entorno ──
# Un keyring es inmutable una vez creado (no se puede renombrar ni mover
# de región) — por eso el nombre incluye el entorno desde el principio,
# igual que el resto de recursos de este proyecto (`oms-<env>-...`).
resource "google_kms_key_ring" "oms" {
  name     = "oms-${var.env}-keyring"
  location = var.region
}

# ─── Clave para Cloud SQL ──────────────────────────────────────────
# NOTA DE DISEÑO: rotación automática cada 90 días — más frecuente que
# el default de Google (que no aplica rotación visible/auditable por el
# cliente), y alineado con el espíritu de REG-GDPR-003 (control y
# trazabilidad real, no solo "confiar en que Google rota su propia
# clave"). `prevent_destroy`: una clave KMS destruida con datos cifrados
# bajo ella vuelve esos datos IRRECUPERABLES — mismo principio de
# defensa que ya aplica `deletion_protection`/`prevent_destroy` en la
# propia instancia de Cloud SQL (modules/database/main.tf).
resource "google_kms_crypto_key" "cloudsql" {
  name            = "oms-${var.env}-cloudsql-key"
  key_ring        = google_kms_key_ring.oms.id
  rotation_period = "7776000s" # 90 días, en segundos (KMS exige el campo en segundos, no días)

  lifecycle {
    prevent_destroy = true
  }
}

# ─── Clave para el bucket de assets/SPA ────────────────────────────
# Clave separada de la de Cloud SQL a propósito: son dos superficies de
# datos distintas (base de datos transaccional vs. objetos estáticos),
# con ciclos de vida y necesidades de rotación potencialmente distintos
# — mismo principio de "una clave, un propósito" que ya sigue el
# proyecto con los Service Accounts (uno de runtime, uno de CI/CD, nunca
# compartidos).
resource "google_kms_crypto_key" "storage" {
  name            = "oms-${var.env}-storage-key"
  key_ring        = google_kms_key_ring.oms.id
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = true
  }
}

# ─── Permiso: la Service Agent de Cloud SQL debe poder USAR la clave ──
# HALLAZGO DE DISEÑO (documentado antes de aplicar, no tras un error real
# — mismo patrón preventivo ya usado en otros módulos de este proyecto):
# Cloud SQL no cifra con una CMEK por sí solo con que la clave exista.
# Necesita permiso explícito de `roles/cloudkms.cryptoKeyEncrypterDecrypter`
# sobre la Service Agent de Cloud SQL DE ESTE PROYECTO — una identidad
# gestionada por Google con un formato fijo y predecible
# (`service-<PROJECT_NUMBER>@gcp-sa-cloud-sql.iam.gserviceaccount.com`),
# distinta del Service Account de runtime que ya declara este proyecto.
# Sin este binding, `terraform apply` sobre `google_sql_database_instance`
# con `encryption_key_name` apuntando a esta clave falla con un 403 real
# de Cloud KMS.
data "google_project" "current" {
  project_id = var.project_id
}

# HALLAZGO REAL (Fase 7, terraform apply real contra staging — primer
# intento de activar CMEK): asumir que la Service Agent de un producto ya
# existe solo porque su nombre es predecible fue INCORRECTO en la
# práctica. Estas identidades gestionadas por Google se aprovisionan de
# forma perezosa — normalmente la primera vez que el propio servicio
# (Cloud SQL, Cloud Storage) hace algo que las requiere dentro de un
# proyecto — y este proyecto nunca antes había usado ninguna función que
# las forzara a existir. El intento real de otorgar el permiso IAM
# directamente falló con dos errores reales encadenados:
#   "Service account service-<N>@gcp-sa-cloud-sql.iam.gserviceaccount.com
#    does not exist" (400, al aplicar el binding de KMS)
#   "Per-Product Per-Project Service Account is not found" (al crear la
#    propia instancia de Cloud SQL con encryption_key_name)
# `google_project_service_identity` (provider google-beta) es el recurso
# que fuerza ese aprovisionamiento de forma explícita y declarativa —
# "creá esta Service Agent si todavía no existe" — en vez de asumir que
# ya está ahí. Los bindings de abajo dependen de él explícitamente
# (`depends_on`) para garantizar el orden correcto: primero aprovisionar
# la identidad, después otorgarle el permiso sobre la clave.
resource "google_project_service_identity" "cloudsql_sa" {
  provider = google-beta
  project  = var.project_id
  service  = "sqladmin.googleapis.com"
}

resource "google_project_service_identity" "storage_sa" {
  provider = google-beta
  project  = var.project_id
  service  = "storage.googleapis.com"
}

resource "google_kms_crypto_key_iam_member" "cloudsql_sa" {
  crypto_key_id = google_kms_crypto_key.cloudsql.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.cloudsql_sa.email}"
  depends_on    = [google_project_service_identity.cloudsql_sa]
}

# HALLAZGO REAL (Fase 7, terraform apply real): a diferencia de la
# Service Agent de Cloud SQL (cuyo `.email` sí quedó poblado por
# google_project_service_identity), la de Cloud Storage devolvió ese
# atributo en `null` — "Invalid template interpolation value: ... is
# null". `google_project_service_identity` sigue siendo necesario para
# FORZAR el aprovisionamiento de la identidad (ver comentario de arriba),
# pero para componer el nombre del miembro del binding se vuelve al
# formato literal ya usado en el diseño original de este módulo
# (`service-<PROJECT_NUMBER>@gs-project-accounts.iam.gserviceaccount.com`
# — mismo patrón fijo y documentado por Google que ya usaba `data
# "google_project" "current"` antes de este hallazgo), en vez de
# depender de un atributo que este recurso no siempre expone.
resource "google_kms_crypto_key_iam_member" "storage_sa" {
  crypto_key_id = google_kms_crypto_key.storage.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
  depends_on    = [google_project_service_identity.storage_sa]
}

# ─── Outputs ──────────────────────────────────────────────────────
# HALLAZGO REAL (continuación del hallazgo de arriba): otorgar el permiso
# IAM sobre la clave no fue suficiente — el error "Per-Product Per-Project
# Service Account is not found" vino de la propia CREACIÓN de la
# instancia de Cloud SQL, que internamente vuelve a intentar resolver esa
# Service Agent en el momento de aprovisionarse con una CMEK. Por eso
# ambos outputs dependen explícitamente (`depends_on`) del binding de IAM
# correspondiente, no solo de la clave — fuerza a Terraform a esperar a
# que la Service Agent exista Y tenga el permiso ANTES de que
# modules/database o modules/compute reciban el ID de la clave y puedan
# empezar a crear/actualizar sus propios recursos.
output "cloudsql_key_id" {
  value       = google_kms_crypto_key.cloudsql.id
  description = "ID completo de la CMEK de Cloud SQL, para pasar a modules/database (encryption_key_name)."
  depends_on  = [google_kms_crypto_key_iam_member.cloudsql_sa]
}

output "storage_key_id" {
  value       = google_kms_crypto_key.storage.id
  description = "ID completo de la CMEK del bucket, para pasar al bucket de assets/SPA."
  depends_on  = [google_kms_crypto_key_iam_member.storage_sa]
}
