# Variables del módulo raíz. Se sobreescriben con envs/<env>.tfvars

variable "project_id" {
  type        = string
  description = "ID del proyecto GCP donde se crea la infraestructura."
}

variable "region" {
  type        = string
  description = "Región principal. REG-GDPR-001 limita a regiones dentro de la UE."
  default     = "europe-west3"
  validation {
    # NOTA DE DISEÑO (agregado por el equipo): `startswith(var.region, "europe-")`
    # NO es suficiente — GCP tiene regiones que empiezan literalmente con
    # "europe-" pero NO están dentro de la Unión Europea: europe-west2
    # (Londres, Reino Unido — fuera de la UE tras el Brexit) y europe-west6
    # (Zúrich, Suiza — nunca fue miembro de la UE). Aceptar cualquiera de
    # esas dos violaría REG-GDPR-001, que exige residencia de datos en la
    # UE, no solo "en Europa geográfica". Se usa una allowlist explícita
    # con las regiones GCP que sí están dentro de la UE (mismo patrón que
    # la validación de `env` de abajo).
    condition = contains([
      "europe-west1",    # Bélgica
      "europe-west3",    # Alemania (Frankfurt) — región primaria del proyecto
      "europe-west4",    # Países Bajos
      "europe-west8",    # Italia (Milán)
      "europe-west9",    # Francia (París)
      "europe-west12",   # Italia (Turín)
      "europe-southwest1", # España (Madrid)
      "europe-north1",   # Finlandia
      "europe-central2", # Polonia (Varsovia) — región DR del bonus multi-region
    ], var.region)
    error_message = "REG-GDPR-001 exige una región dentro de la UE (europe-west1/3/4/8/9/12, europe-southwest1, europe-north1 o europe-central2) — no basta con que el nombre empiece por 'europe-' (europe-west2/Londres y europe-west6/Zúrich están fuera de la UE)."
  }
}

variable "env" {
  type        = string
  description = "Nombre del entorno: staging | production."
  validation {
    condition     = contains(["staging", "production"], var.env)
    error_message = "env debe ser 'staging' o 'production'."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR /16 de la VPC."
  default     = "10.20.0.0/16"
}

variable "db_tier" {
  type        = string
  description = "Tier de Cloud SQL. Cambia entre entornos."
  # TODO(alumno): elige tier sensato por entorno (ej. db-custom-2-7680 en staging,
  # db-custom-4-15360 en producción) y reflexiona en el README por qué.
}

variable "cloud_run_min_instances" {
  type        = number
  description = "Mínimo de instancias de Cloud Run."
  default     = 0
}

variable "cloud_run_max_instances" {
  type        = number
  description = "Máximo de instancias (NFR-SCAL-001 — pico 5×)."
  default     = 10
}

variable "image_repo" {
  type        = string
  description = "Repositorio de Artifact Registry (ej. europe-west3-docker.pkg.dev/<proj>/oms)."
}

variable "image_sha" {
  type        = string
  description = "SHA256 de la imagen a desplegar (formato sha256:abc...). MISMO valor en staging y producción."
}

variable "deletion_protection" {
  type        = bool
  description = "Habilita deletion_protection en Cloud SQL. SIEMPRE true en producción."
  default     = true
}

variable "github_repository" {
  type        = string
  description = "Repo GitHub que puede impersonar el SA vía WIF (formato owner/repo)."
  default     = "acme-org/oms-platform"
}
