# ── Módulo: DATABASE ───────────────────────────────────────────────
# Cloud SQL PostgreSQL multi-zone (NFR-AVAIL-001) + Memorystore Redis (NFR-PERF-001).
# Password gestionada en Secret Manager — NUNCA en variables ni en tfstate plano.

variable "project_id" { type = string }
variable "region" { type = string }
variable "env" { type = string }
variable "network_id" { type = string }
variable "private_subnet_id" { type = string }
variable "db_tier" { type = string }
variable "deletion_protection" { type = bool }
variable "labels" { type = map(string) }
# Agregado por el equipo (hallazgo de la Fase 1): se usa solo para forzar
# con `depends_on` que Cloud SQL y Redis esperen a que la conexión de
# peering del módulo `network` exista de verdad antes de intentar crearse
# — sin esto, Terraform puede lanzarlos en paralelo y fallan con
# "network doesn't have at least 1 private services connection".
variable "private_vpc_connection_id" { type = string }
# Agregado por el equipo (Fase 7, bonus CMEK): ID completo de la clave KMS
# gestionada por el proyecto (module.kms), en vez de la clave default de
# Google. Nullable a propósito (default ""): permite que este módulo siga
# funcionando sin CMEK si algún día se quisiera desactivar el bonus sin
# tocar el resto del módulo.
variable "cmek_key_id" {
  type    = string
  default = ""
}

# ─── Password aleatoria gestionada por GCP en Secret Manager ──────
#
# NOTA DE DISEÑO (agregado por el equipo): el recurso `google_secret_manager_secret`
# de abajo solo crea el CONTENEDOR del secreto (como una carpeta vacía) —
# todavía no tiene ningún valor dentro. El valor real se genera con
# `random_password` (provider "random", ya declarado en versions.tf) y se
# guarda dentro del contenedor con `google_secret_manager_secret_version`.
# Terraform nunca escribe la contraseña como texto literal en ningún punto
# del código: la genera él mismo en el momento del `apply` y la encadena
# entre recursos por referencia (`random_password.db_password.result`).
resource "random_password" "db_password" {
  length  = 32
  special = true
  # Cloud SQL Postgres rechaza algunos caracteres especiales en la
  # password si se pasan por CLI/API sin escapar correctamente; se
  # restringe el conjunto a uno seguro y ampliamente soportado.
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "oms-${var.env}-db-password"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
  labels = var.labels
}

# Agregado por el equipo: crea la VERSIÓN del secreto con el valor generado
# por random_password. Sin esto, el secreto existiría pero estaría vacío.
resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# ─── Cloud SQL PostgreSQL ─────────────────────────────────────────
resource "google_sql_database_instance" "main" {
  name                = "oms-${var.env}-postgres"
  database_version    = "POSTGRES_16" # pin EXPLÍCITO — no dejar en mayor genérica
  region              = var.region
  deletion_protection = var.deletion_protection

  # BONUS (Fase 7, ver TODO original ya resuelto más abajo): CMEK propia
  # en vez de la clave default de Google — module.kms crea el keyring +
  # la clave y otorga el permiso necesario a la Service Agent de Cloud
  # SQL. `encryption_key_name` es INMUTABLE tras la creación de la
  # instancia (GCP no permite "re-cifrar" una instancia existente con otra
  # clave sin recrearla) — por eso se pasa desde el primer `apply` donde
  # se active, nunca como una actualización posterior sobre una instancia
  # ya existente.
  encryption_key_name = var.cmek_key_id != "" ? var.cmek_key_id : null

  settings {
    tier              = var.db_tier
    availability_type = "REGIONAL" # NFR-AVAIL-001 multi-zone HA
    disk_size         = 100
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    # HALLAZGO REAL (Fase 7, verificación bonus CMEK): existen DOS campos
    # de protección distintos y fácilmente confundibles en este recurso:
    #   - `deletion_protection` (nivel superior, ya usado arriba): una
    #     protección del LADO DE TERRAFORM, evita que un `terraform
    #     destroy`/plan de reemplazo siquiera lo intente.
    #   - `settings.deletion_protection_enabled` (este campo, nunca antes
    #     declarado en este código): el flag REAL que la propia API de
    #     Cloud SQL consulta al procesar una solicitud de borrado — vive
    #     "por debajo" del anterior y es independiente de él.
    # Sin declarar este segundo campo explícitamente, Terraform nunca lo
    # actualiza (queda fuera de su control, "null" en el plan) — aunque el
    # de nivel superior cambiara a `false` y el `plan` lo mostrara
    # correctamente, la API real seguía rechazando el borrado real con
    # "failed to delete instance because deletion_protection is set to
    # true", porque el campo que la API realmente mira nunca se tocó. Se
    # declara aquí, ligado a la MISMA variable, para que ambos cambien
    # siempre juntos y no puedan desincronizarse otra vez.
    deletion_protection_enabled = var.deletion_protection

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 14 # OPS-005: PITR 14d
      }
      start_time = "03:00" # backup nocturno
    }

    maintenance_window {
      day  = 7 # domingo
      hour = 4
    }

    ip_configuration {
      ipv4_enabled    = false # NUNCA expuesto a internet
      private_network = var.network_id
      # HALLAZGO REAL (Fase 6, detectado con Trivy config — GCP-0015, HIGH):
      # sin este campo, Cloud SQL admite conexiones SIN cifrar además de las
      # cifradas. ENCRYPTED_ONLY exige TLS en TODAS las conexiones, incluso
      # dentro de la red privada — coherente con REG-GDPR-001 (protección
      # de datos) y con "cero credenciales en texto plano" que ya rige el
      # proyecto. La conexión vía socket de Cloud Run (Cloud SQL Proxy
      # integrado) ya cifra por diseño, así que esto no rompe nada existente.
      ssl_mode = "ENCRYPTED_ONLY"
    }

    # NOTA DE DISEÑO (agregado por el equipo): "database_flags" son el
    # equivalente gestionado de editar postgresql.conf a mano — Cloud SQL
    # no da acceso directo al sistema de archivos del servidor, así que
    # estos parámetros de configuración se ajustan aquí.
    database_flags {
      name = "log_min_duration_statement"
      # Registra en el log cualquier consulta que tarde más de 400ms —
      # el mismo umbral que NFR-PERF-002 exige para POST /api/orders p95.
      # Sin esto, sería imposible saber QUÉ consulta concreta está
      # causando una latencia alta si el sistema empieza a responder mal.
      value = "400"
    }
    database_flags {
      name = "log_statement"
      # 'ddl' registra solo cambios de ESTRUCTURA (CREATE/ALTER/DROP TABLE),
      # no las consultas normales de datos — es una medida de auditoría de
      # cambios de esquema (quién y cuándo), no de tráfico general, así que
      # no infla el volumen de logs con cada SELECT/INSERT normal.
      value = "ddl"
    }
    database_flags {
      name = "log_connections"
      # Registra cada nueva conexión a la base de datos — apoya la
      # trazabilidad de accesos que exige REG-GDPR-003 (audit trail).
      value = "on"
    }

    # HALLAZGO REAL (Fase 6, detectado con Trivy config — GCP-0014/0020/0022/
    # 0025, todas MEDIUM): 4 flags de logging recomendados que faltaban.
    # Nota sobre GCP-0021 (LOW, "log_statement no debería estar activo"):
    # NO se cambia `log_statement=ddl` de arriba a "none" — ese aviso genérico
    # de Trivy no distingue el matiz ya documentado: "ddl" registra SOLO
    # cambios de esquema (CREATE/ALTER/DROP), nunca datos de negocio ni
    # valores de columnas, así que no expone información sensible pese a
    # activar el flag. Se prefiere mantenerlo por el valor de auditoría que
    # ya justifica el comentario original.
    database_flags {
      name = "log_disconnections"
      # Complementa log_connections: permite calcular duración de sesión y
      # detectar patrones anómalos de desconexión (posible vector de DoS).
      value = "on"
    }
    database_flags {
      name = "log_lock_waits"
      # Registra cuando una consulta espera por un lock — indicador temprano
      # de contención/deadlocks y de un posible vector de denegación de
      # servicio antes de que degrade el NFR-PERF-002.
      value = "on"
    }
    database_flags {
      name = "log_checkpoints"
      # Los checkpoints de PostgreSQL son operaciones de I/O pesadas — su
      # frecuencia/duración es un diagnóstico temprano de problemas de
      # rendimiento del propio motor, no solo de las consultas de la app.
      value = "on"
    }
    database_flags {
      name = "log_temp_files"
      # Registra archivos temporales en disco por encima de este umbral en
      # bytes (0 = registrar todos). Consultas que generan archivos
      # temporales suelen indicar un plan de ejecución ineficiente (falta de
      # índice, sort en memoria insuficiente) — señal útil antes de que se
      # traduzca en latencia visible para el usuario.
      value = "0"
    }

    user_labels = var.labels
  }

  lifecycle {
    # HALLAZGO REAL (Fase 7, verificación real del bonus CMEK): al activar
    # `enable_cmek=true` por primera vez, `encryption_key_name` cambia de
    # null a un valor real — GCP marca ese campo como "forces replacement"
    # (es inmutable, no se puede aplicar a una instancia ya existente sin
    # recrearla). Con `prevent_destroy = true` activo, `terraform plan`
    # fallaba en seco:
    #   "Error: Instance cannot be destroyed ... has lifecycle.prevent_destroy
    #    set, but the plan calls for this resource to be destroyed."
    # Comportamiento CORRECTO de la protección — no es un bug a silenciar
    # sin más. Se bajó y restauró dos veces durante la Fase 7 (staging y
    # producción, ambas recreaciones conscientes con CMEK).
    #
    # Bajada de nuevo, esta vez de forma DEFINITIVA, para el cierre real
    # del proyecto (`terraform destroy` de ambos entornos completos, tras
    # grabar el video de explicación — decisión ya tomada por el usuario
    # desde el inicio, para no seguir gastando el crédito de $300/90 días).
    # No hay ninguna razón para restaurarla después de esto: el propio
    # entorno deja de existir.
    prevent_destroy = false
  }

  # NOTA DE DISEÑO (agregado por el equipo, hallazgo real durante el primer
  # `apply` a staging): sin este depends_on explícito, Terraform intentó
  # crear esta instancia EN PARALELO con la conexión de peering del módulo
  # network (no hay ninguna referencia directa entre sus argumentos que
  # imponga el orden — `private_network = var.network_id` apunta a la VPC,
  # no a la conexión de peering en sí). El resultado fue el error real:
  # "the network doesn't have at least 1 private services connection".
  depends_on = [var.private_vpc_connection_id]
}

# ─── Base de datos para el OMS ────────────────────────────────────
resource "google_sql_database" "oms" {
  name     = "oms"
  instance = google_sql_database_instance.main.name
}

# ─── Usuario de aplicación con password gestionada ────────────────
#
# NOTA DE DISEÑO (agregado por el equipo): se eligió la opción
# random_password + Secret Manager (frente a "password_policy" con
# manage_master_user_password, donde ni Terraform vería la password) por
# dar más control operativo para rotarla manualmente si hace falta, siendo
# el patrón más estándar y documentado para Terraform + Cloud SQL.
#
# El valor jamás aparece como texto literal: se referencia directamente
# desde el recurso `random_password` de arriba. Terraform sí conoce el
# valor internamente (queda en el tfstate, protegido por los permisos del
# bucket gs://acmeoms-<env>-fatm-tfstate creado en la Fase 0), pero nunca
# se escribe a mano ni aparece en el historial de git.
resource "google_sql_user" "oms" {
  name     = "oms_app"
  instance = google_sql_database_instance.main.name
  password = random_password.db_password.result
}

# ─── Memorystore Redis Standard (HA) ──────────────────────────────
resource "google_redis_instance" "cache" {
  name           = "oms-${var.env}-redis"
  tier           = "STANDARD_HA" # NFR-AVAIL-001: replica automática
  memory_size_gb = var.env == "production" ? 5 : 1
  region         = var.region

  authorized_network = var.network_id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  redis_version           = "REDIS_7_2"
  transit_encryption_mode = "SERVER_AUTHENTICATION"
  auth_enabled            = true

  labels = var.labels

  # Mismo motivo que en google_sql_database_instance.main (ver comentario
  # ahí arriba): Redis con connect_mode = PRIVATE_SERVICE_ACCESS también
  # depende de que la conexión de peering exista antes de intentar crearse.
  depends_on = [var.private_vpc_connection_id]
}

# ─── Outputs ──────────────────────────────────────────────────────
output "db_connection_name" { value = google_sql_database_instance.main.connection_name }
output "db_private_ip" { value = google_sql_database_instance.main.private_ip_address }
output "db_password_secret_id" { value = google_secret_manager_secret.db_password.secret_id }

output "redis_host" { value = google_redis_instance.cache.host }
output "redis_port" { value = google_redis_instance.cache.port }
output "redis_auth_secret" {
  value     = google_redis_instance.cache.auth_string
  sensitive = true
}
