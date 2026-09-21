# Configuración del backend remoto de Terraform para STAGING.
# Se usa con: terraform init -backend-config=envs/staging.backend.hcl
#
# No contiene secretos ni credenciales — solo el nombre del bucket (ya
# creado en la Fase 0, ver oms-platform/BITACORA-COMANDOS.md § 0.7) y el
# prefijo de ruta dentro de ese bucket donde vivirá el archivo de estado.

bucket = "acmeoms-staging-fatm-tfstate"
prefix = "oms-platform/staging"
