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

# image_sha REAL (Fase 3): digest obtenido tras `docker push` de un
# placeholder minimo de infraestructura (oms-platform/docker/server.js —
# NO es la aplicación OMS real, ver Trabajo - enunciado.md sección 1).
# Ver oms-platform/BITACORA-COMANDOS.md Fase 3 para el proceso completo.
# NOTA: este digest ya corresponde a la versión con endpoint /health (no
# /healthz — ver hallazgo real documentado en BITACORA-COMANDOS.md § 3.3:
# Google Front End interceptaba /healthz antes de llegar a Cloud Run).
image_repo = "europe-west3-docker.pkg.dev/acmeoms-staging-fatm/oms/oms"
image_sha  = "sha256:fcd5c9483453625e40a4989a2edeee82a9ce6dbc78cef6c54ceabf5bcec82b25"

deletion_protection = true             # también en staging

github_repository = "ftoscanomarquez/acmeoms-infraestructura"
