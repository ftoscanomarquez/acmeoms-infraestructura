# ── Entorno: STAGING ────────────────────────────────────────────────
# Tier reducido, autoscaling mínimo, deletion_protection sigue ACTIVADO
# (es buena práctica protegerlo también en staging).

project_id = "acmeoms-staging-fatm" # proyecto GCP real de staging (Fase 0)
region     = "europe-west3"         # REG-GDPR-001
env        = "staging"

vpc_cidr = "10.20.0.0/16"

db_tier = "db-custom-2-7680" # 2 vCPU, 7.5 GB RAM

cloud_run_min_instances = 0       # escala a cero cuando no hay tráfico
cloud_run_max_instances = 5       # tope conservador para staging
cloud_run_cpu           = "1000m" # explícito: antes hardcodeado en el módulo (Fase 5, ver hallazgo)
cloud_run_memory        = "2Gi"   # debe coincidir con ansible/group_vars/staging.yml

# image_sha REAL (Fase 5, v0.2.0): digest tras `docker push` del cambio
# mínimo (server.js: campo "version" en /health) hecho para verificar de
# punta a punta el ciclo build → deploy staging → deploy producción con
# canary real → rollback (ver BITACORA-COMANDOS.md Fase 5, verificación
# final). Recordatorio: este valor solo importa en el PRIMER apply — está
# en lifecycle.ignore_changes, el despliegue real lo controla Ansible.
image_repo = "europe-west3-docker.pkg.dev/acmeoms-staging-fatm/oms/oms"
image_sha  = "sha256:d68ca4fc59a42a8f6bb74e9f82d937f545315230c7bc214880d1310907c62f72"

# CIERRE DEL PROYECTO (terraform destroy real de ambos entornos, tras
# grabar el video — decisión ya tomada desde el inicio del trabajo): se
# baja de forma definitiva para permitir la destrucción real de Cloud
# SQL. Ver el mismo motivo, con más detalle, en modules/database/main.tf.
deletion_protection = false # ⚠️ DEFINITIVO — cierre del proyecto, el entorno completo se destruye

github_repository = "ftoscanomarquez/acmeoms-infraestructura"

# BONUS (Fase 7): CMEK propia en vez de la clave default de Google, para
# Cloud SQL y el bucket de assets/SPA (terraform/modules/kms). Activado
# desde staging primero — decisión real: no hay datos de negocio reales
# en juego (solo el placeholder de infraestructura), así que recrear
# Cloud SQL con encryption_key_name (campo inmutable, exige destroy+create)
# no tiene ningún riesgo real aquí. Ver BITACORA-COMANDOS.md § 7.x para el
# detalle completo de la verificación.
enable_cmek = true
