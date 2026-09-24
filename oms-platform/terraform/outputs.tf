output "load_balancer_ip" {
  description = "IP global del HTTPS Load Balancer."
  value       = module.compute.load_balancer_ip
}

output "cloud_run_url" {
  description = "URL del servicio Cloud Run del OMS."
  value       = module.compute.cloud_run_url
}

output "db_connection_name" {
  description = "Connection name de Cloud SQL (proj:region:instance)."
  value       = module.database.db_connection_name
  sensitive   = false
}

output "redis_host" {
  description = "Host privado de Memorystore Redis."
  value       = module.database.redis_host
  sensitive   = false
}

output "workload_identity_provider" {
  description = "Provider de WIF para configurar en GitHub Actions."
  value       = module.iam.workload_identity_provider
}

output "cicd_service_account" {
  description = "Service Account que asumen los workflows de CI/CD."
  value       = module.iam.cicd_service_account_email
}

output "artifact_registry_url" {
  description = "URL del repositorio de Artifact Registry (útil para CI/CD y para componer la imagen completa)."
  value       = module.compute.artifact_registry_url
}

# ─── Outputs consumidos por Ansible (deploy.yml) ──────────────────
# HALLAZGO REAL (Fase 5, ver BITACORA-COMANDOS.md § 5.9/5.10): cpu/memory/
# min/max_instances vivían DUPLICADOS a mano en ansible/group_vars/<env>.yml
# y aquí en terraform/envs/<env>.tfvars — nada los mantenía sincronizados,
# y de hecho se detectó un drift real (memory quedó desalineada silenciosamente
# durante varias fases). Se exponen aquí como outputs para que Ansible los
# LEA directamente con `terraform output -json` en vez de mantener su propia
# copia — Terraform pasa a ser la ÚNICA fuente de verdad de la "forma" del
# contenedor; group_vars/<env>.yml solo declara lo que es exclusivo de
# Ansible (traffic_percent, health_path, slack_channel, etc).
output "cloud_run_cpu" {
  description = "CPU del contenedor de Cloud Run — fuente de verdad para Ansible."
  value       = var.cloud_run_cpu
}

output "cloud_run_memory" {
  description = "Memoria del contenedor de Cloud Run — fuente de verdad para Ansible."
  value       = var.cloud_run_memory
}

output "cloud_run_min_instances" {
  description = "Mínimo de instancias de Cloud Run — fuente de verdad para Ansible."
  value       = var.cloud_run_min_instances
}

output "cloud_run_max_instances" {
  description = "Máximo de instancias de Cloud Run — fuente de verdad para Ansible."
  value       = var.cloud_run_max_instances
}
