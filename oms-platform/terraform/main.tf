# Composition root del trabajo final.
# Cada módulo encapsula una capa de la arquitectura del OMS.

# ┌─────────────────────────────────────────────────────────┐
# │ Backend de estado en GCS.                                │
# └─────────────────────────────────────────────────────────┘
# NOTA DE DISEÑO (agregado por el equipo): el bloque `backend` se procesa
# ANTES de que Terraform lea var.env o cualquier .tfvars — es literalmente
# el primer paso de `terraform init`. Por eso NO admite interpolación de
# variables (`${var.env}` aquí sería un error). El bucket real (que sí
# cambia entre staging y producción — creados en la Fase 0 como
# acmeoms-staging-fatm-tfstate y acmeoms-production-fatm-tfstate) se pasa
# por fuera, en el momento del init, con `-backend-config`:
#
#   # Staging:
#   terraform init -backend-config="bucket=acmeoms-staging-fatm-tfstate" \
#                   -backend-config="prefix=oms-platform/staging"
#
#   # Producción:
#   terraform init -backend-config="bucket=acmeoms-production-fatm-tfstate" \
#                   -backend-config="prefix=oms-platform/production"
#
# El bloque de abajo se deja intencionalmente VACÍO de valores concretos —
# solo declara que el backend es de tipo "gcs"; los valores reales llegan
# siempre por -backend-config, nunca hardcodeados aquí (así el mismo código
# sirve para ambos entornos, sin tocar este archivo al cambiar de bucket).
terraform {
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Localización lógica del proyecto (etiquetas comunes).
locals {
  common_labels = {
    project    = "oms"
    env        = var.env
    managed_by = "terraform"
    module     = "platform"
  }
}

# ┌─────────────────────────────────────────────────────────┐
# │ Capa de red                                             │
# └─────────────────────────────────────────────────────────┘
module "network" {
  source = "./modules/network"

  project_id = var.project_id
  region     = var.region
  env        = var.env
  vpc_cidr   = var.vpc_cidr
  labels     = local.common_labels
}

# ┌─────────────────────────────────────────────────────────┐
# │ Capa de datos: Cloud SQL Postgres + Memorystore Redis   │
# └─────────────────────────────────────────────────────────┘
module "database" {
  source = "./modules/database"

  project_id          = var.project_id
  region              = var.region
  env                 = var.env
  network_id          = module.network.network_id
  private_subnet_id   = module.network.private_subnet_id
  db_tier             = var.db_tier
  deletion_protection = var.deletion_protection
  labels              = local.common_labels
  # Agregado por el equipo (hallazgo Fase 1): fuerza el orden correcto de
  # creación entre la conexión de peering (module.network) y Cloud
  # SQL/Redis (module.database) — ver comentarios en modules/database/main.tf.
  private_vpc_connection_id = module.network.private_vpc_connection_id
}

# ┌─────────────────────────────────────────────────────────┐
# │ Capa de cómputo: Cloud Run + Load Balancer + CDN        │
# └─────────────────────────────────────────────────────────┘
module "compute" {
  source = "./modules/compute"

  project_id              = var.project_id
  region                  = var.region
  env                     = var.env
  image_repo              = var.image_repo
  image_sha               = var.image_sha
  cloud_run_min_instances = var.cloud_run_min_instances
  cloud_run_max_instances = var.cloud_run_max_instances
  cloud_run_cpu           = var.cloud_run_cpu
  cloud_run_memory        = var.cloud_run_memory
  db_connection_name      = module.database.db_connection_name
  db_secret_id            = module.database.db_password_secret_id
  redis_host              = module.database.redis_host
  connector_subnet_id     = module.network.connector_subnet_id
  connector_subnet_name   = module.network.connector_subnet_name
  lb_domain               = var.lb_domain
  labels                  = local.common_labels
}

# ┌─────────────────────────────────────────────────────────┐
# │ Capa IAM: Service Accounts + Workload Identity Federation│
# └─────────────────────────────────────────────────────────┘
module "iam" {
  source = "./modules/iam"

  project_id         = var.project_id
  env                = var.env
  github_repository  = var.github_repository
  cloud_run_sa       = module.compute.cloud_run_service_account
  labels             = local.common_labels
  staging_project_id = var.staging_project_id
}
