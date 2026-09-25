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
      "europe-west1",      # Bélgica
      "europe-west3",      # Alemania (Frankfurt) — región primaria del proyecto
      "europe-west4",      # Países Bajos
      "europe-west8",      # Italia (Milán)
      "europe-west9",      # Francia (París)
      "europe-west12",     # Italia (Turín)
      "europe-southwest1", # España (Madrid)
      "europe-north1",     # Finlandia
      "europe-central2",   # Polonia (Varsovia) — región DR del bonus multi-region
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
  description = "Máximo de instancias (NFR-SCAL-001 — pico 5×, sujeto a cuota real de CPU/memoria por región)."
  default     = 10
}

# HALLAZGO REAL (Fase 5, ver BITACORA-COMANDOS.md § 5.9): antes hardcodeados
# dentro de modules/compute/main.tf ("1000m"/"2Gi" fijos, iguales en ambos
# entornos) mientras que ansible/group_vars/production.yml pedía 2000m —
# Ansible intentaba "corregir" una CPU que Terraform ya había fijado más
# baja, y la coexistencia de ambas revisiones (la vieja de Terraform + la
# nueva que Ansible intentaba crear) excedía la cuota CpuAllocPerProjectRegion.
# Ahora Terraform es la única fuente de verdad de la "forma" del contenedor
# (mismo principio ya aplicado a min/max_instances); Ansible solo debe
# COMPARAR contra estos valores exactos, nunca cambiarlos por su cuenta.
variable "cloud_run_cpu" {
  type        = string
  description = "CPU del contenedor de Cloud Run (formato milicores, ej. \"1000m\"). Debe coincidir con ansible/group_vars/<env>.yml."
  default     = "1000m"
}

variable "cloud_run_memory" {
  type        = string
  description = "Memoria del contenedor de Cloud Run (ej. \"2Gi\"). Debe coincidir con ansible/group_vars/<env>.yml."
  default     = "2Gi"
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

# HALLAZGO REAL (Fase 6, ver BITACORA-COMANDOS.md § 6.18): la promoción de
# imagen a producción incluye copiar también la FIRMA de Cosign con
# `cosign copy` (la firma no viaja con un simple docker tag+push, ver
# hallazgo 6.17) — esa operación necesita LEER del Artifact Registry de
# staging y ESCRIBIR en el de producción en la misma llamada. Solo tiene
# sentido en `production.tfvars` (staging no necesita leer de sí mismo);
# se deja vacío por defecto para que aplicar el módulo en staging no
# intente crear un binding sin sentido.
variable "staging_project_id" {
  type        = string
  description = "ID del proyecto GCP de staging — SOLO usado en producción, para dar al SA de CI/CD de producción permiso de lectura sobre el Artifact Registry de staging (necesario para 'cosign copy' al promocionar). Vacío en staging."
  default     = ""
}

# Agregado por el equipo (Fase 2): dominio para el certificado SSL managed
# del Load Balancer. Requiere un dominio real registrado (no lo cubre GCP)
# con un registro DNS tipo A hacia la IP del Load Balancer — ver
# BITACORA-COMANDOS.md Fase 2 para el detalle completo de esta decisión.
# Mientras no exista un dominio real, el certificado se crea igual pero
# queda en estado "PROVISIONING" sin bloquear el resto del despliegue.
variable "lb_domain" {
  type        = string
  description = "Dominio para el certificado SSL managed del Load Balancer (requiere DNS real apuntando a la IP del LB)."
  # En minúsculas: GCP normaliza el campo `domains` del certificado a
  # minúsculas al crearlo — con mayúsculas, Terraform detecta diferencia
  # permanente y fuerza destruir/recrear el certificado en cada apply.
  default = "pendiente-dominio-real.example.com"
}

# Agregado por el equipo (Fase 7, bonus CMEK): interruptor único para
# activar/desactivar el módulo kms completo. `false` por defecto — activar
# CMEK sobre una instancia de Cloud SQL YA EXISTENTE sin CMEK exige
# recrearla (encryption_key_name es inmutable, ver modules/database), así
# que este flag se decide una vez y se documenta la decisión real tomada
# para cada entorno en envs/<env>.tfvars, no se cambia por capricho.
variable "enable_cmek" {
  type        = bool
  description = "Activa CMEK propia (Cloud KMS) para Cloud SQL y el bucket de assets, en vez de las claves default de Google (bonus del enunciado)."
  default     = false
}
