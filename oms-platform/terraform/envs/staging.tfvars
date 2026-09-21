# ── Entorno: STAGING ────────────────────────────────────────────────
# Tier reducido, autoscaling mínimo, deletion_protection sigue ACTIVADO
# (es buena práctica protegerlo también en staging).

project_id = "acmeoms-staging-fatm"    # proyecto GCP real de staging (Fase 0)
region     = "europe-west3"            # REG-GDPR-001
env        = "staging"

vpc_cidr   = "10.20.0.0/16"

db_tier    = "db-custom-2-7680"        # 2 vCPU, 7.5 GB RAM

cloud_run_min_instances = 0            # escala a cero cuando no hay tráfico
cloud_run_max_instances = 5            # tope conservador para staging

# NOTA: image_repo/image_sha se completan de verdad en la Fase 3 (build +
# push de la imagen Docker a Artifact Registry). No afectan al plan/apply
# dirigido de la Fase 1 (-target=module.network -target=module.database),
# que no toca el módulo `compute` — pero Terraform exige un valor sintácticamente
# válido para poder parsear las variables, así que se deja un placeholder
# explícito que fallaría de forma obvia si se usara antes de tiempo.
image_repo = "europe-west3-docker.pkg.dev/acmeoms-staging-fatm/oms"
image_sha  = "sha256:0000000000000000000000000000000000000000000000000000000000PENDIENTE_FASE_3"

deletion_protection = true             # también en staging

github_repository = "ftoscanomarquez/acmeoms-infraestructura"
