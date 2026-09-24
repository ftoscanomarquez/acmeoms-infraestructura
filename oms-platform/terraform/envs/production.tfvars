# ── Entorno: PRODUCTION ─────────────────────────────────────────────
# Tier mayor, autoscaling con piso mínimo > 0 (latencia consistente),
# deletion_protection OBLIGATORIO.
#
# ⚠ La ÚNICA diferencia legítima respecto a staging.tfvars debería ser:
#    - project_id (otro proyecto)
#    - db_tier (más capacidad)
#    - cloud_run_min/max_instances (más réplicas)
#    - image_sha (cuando promocionas, este valor cambia)
#
# Si te encuentras cambiando algo más, replantéatelo.

project_id = "acmeoms-production-fatm" # proyecto GCP real de producción (Fase 0), distinto al de staging
region     = "europe-west3"            # REG-GDPR-001
env        = "production"

vpc_cidr = "10.20.0.0/16"

db_tier = "db-custom-4-15360" # 4 vCPU, 15 GB RAM

cloud_run_min_instances = 2 # nunca a cero: latencia consistente
# NFR-SCAL-001 pedía pico 5× (25 instancias a 2000m CPU cada una = 50000m),
# pero la cuota gratuita por región de Cloud Run es CpuAllocPerProjectRegion
# = 20000m total (ver hallazgo real en BITACORA-COMANDOS.md § 5.4/5.9).
# cpu/memory antes vivían hardcodeados en el módulo (1000m/2Gi) sin relación
# con este archivo — ahora están parametrizados aquí explícitamente.
#
# HALLAZGO REAL adicional: Cloud Run NO acepta cualquier valor de CPU — solo
# valores fraccionarios entre 0.08 y 1.0, o enteros exactos (1.0, 2.0, 4.0,
# 6.0, 8.0). Un intento con "1500m" (1.5 CPU) fue rechazado por la API:
# "Invalid value ... Must be equal to one of [.08-1], 1.0, 2.0, 4.0, 6.0, 8.0".
#
# Elegido 15 instancias × 1000m = 15000m: deja 5000m (25%) de margen real
# bajo el límite de 20000m, con la misma CPU por instancia que el valor
# original (1000m, ya validado), a cambio de menos instancias concurrentes
# que el NFR pedía (25). Desviación documentada del NFR-SCAL-001, por
# restricción real de cuota + valores válidos de CPU de la plataforma.
cloud_run_max_instances = 15
cloud_run_cpu           = "1000m"
cloud_run_memory        = "2Gi" # sin cambios; ya estaba en el límite razonable

# image_sha REAL (Fase 5, v0.2.0): MISMO digest exacto ya validado en
# staging (envs/staging.tfvars) — regla innegociable del enunciado:
# promocionar a producción es desplegar la imagen YA PROBADA, nunca
# reconstruirla ni usar un SHA distinto (penalización de -10 pts si difiere).
# Recordatorio: este valor solo importa en el PRIMER apply (ignore_changes).
image_repo = "europe-west3-docker.pkg.dev/acmeoms-production-fatm/oms/oms"
image_sha  = "sha256:d68ca4fc59a42a8f6bb74e9f82d937f545315230c7bc214880d1310907c62f72"

deletion_protection = true # innegociable

github_repository = "ftoscanomarquez/acmeoms-infraestructura"
