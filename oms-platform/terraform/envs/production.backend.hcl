# Configuración del backend remoto de Terraform para PRODUCCIÓN.
# Se usa con: terraform init -backend-config=envs/production.backend.hcl
#
# No contiene secretos ni credenciales — solo el nombre del bucket (ya
# creado en la Fase 0, ver oms-platform/BITACORA-COMANDOS.md § 0.7) y el
# prefijo de ruta dentro de ese bucket donde vivirá el archivo de estado.
#
# Es un bucket DISTINTO al de staging (proyecto GCP separado), garantizando
# aislamiento total del estado entre ambos entornos.

bucket = "acmeoms-production-fatm-tfstate"
prefix = "oms-platform/production"
