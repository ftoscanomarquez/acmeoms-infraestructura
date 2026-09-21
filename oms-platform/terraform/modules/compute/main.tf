# ── Módulo: COMPUTE ───────────────────────────────────────────────
# Cloud Run para el monolito OMS + HTTPS Load Balancer + Cloud CDN.
# Cloud Run es stateless: NFR-SCAL-001 (autoescalado horizontal hasta 5×).

variable "project_id"              { type = string }
variable "region"                  { type = string }
variable "env"                     { type = string }
variable "image_repo"              { type = string }
variable "image_sha"               { type = string }
variable "cloud_run_min_instances" { type = number }
variable "cloud_run_max_instances" { type = number }
variable "db_connection_name"      { type = string }
variable "db_secret_id"            { type = string }
variable "redis_host"              { type = string }
variable "labels"                  { type = map(string) }
# Agregado por el equipo: subred dedicada (preparada en el módulo network,
# Fase 1) para el VPC Access Connector que permite a Cloud Run alcanzar
# Memorystore Redis por IP privada.
variable "connector_subnet_id"     { type = string }
# Agregado por el equipo: dominio para el certificado SSL managed del Load
# Balancer. DECISIÓN DOCUMENTADA (ver BITACORA-COMANDOS.md Fase 2): un
# dominio real es un recurso que se compra por separado a un registrador
# (no lo provee ni lo cubre el crédito de GCP) y requiere un registro DNS
# tipo A apuntando a la IP del Load Balancer para que Google pueda
# verificarlo y emitir el certificado. Mientras no exista ese dominio real,
# se usa un placeholder explícito — el certificado se crea igual pero
# queda en estado "PROVISIONING" indefinidamente (no bloquea el resto del
# despliegue). Cloud Run sigue siendo accesible por su propia URL nativa
# con HTTPS ya válido (output cloud_run_url) mientras tanto.
variable "lb_domain" {
  type    = string
  default = "PENDIENTE-DOMINIO-REAL.example.com"
}

# ─── Service Account dedicada al runtime ──────────────────────────
resource "google_service_account" "cloud_run" {
  account_id   = "oms-${var.env}-runtime"
  display_name = "OMS ${var.env} — Cloud Run runtime SA"
  description  = "Identidad del servicio Cloud Run. Bindings mínimos en módulo iam."
}

# ─── VPC Access Connector (Cloud Run → Redis por IP privada) ──────
# NOTA DE DISEÑO (agregado por el equipo): Cloud Run, por defecto, vive
# FUERA de la VPC (en la red gestionada de Google) y no tiene visibilidad
# de recursos privados como Memorystore Redis (que deliberadamente no
# tiene IP pública). El VPC Access Connector es el puente: un recurso que
# vive DENTRO de una subred de la VPC (la subred `connector`, preparada en
# el módulo network en la Fase 1 específicamente para este propósito) y
# actúa de intermediario — Cloud Run le envía el tráfico destinado a la
# red privada, y el connector lo reenvía hasta la IP privada de Redis.
resource "google_vpc_access_connector" "redis" {
  name    = "oms-${var.env}-connector"
  region  = var.region
  subnet {
    name = var.connector_subnet_id
  }
  # Rango de instancias del connector: mínimo 2 (alta disponibilidad básica
  # del propio connector), máximo 3 — tráfico esperado bajo (solo llamadas
  # internas a Redis), no requiere escalar más.
  min_instances = 2
  max_instances = 3
}

# ─── Cloud Run service ────────────────────────────────────────────
# Despliega la imagen referenciada por DIGEST (image_sha) — nunca por tag mutable.
resource "google_cloud_run_v2_service" "oms" {
  name     = "oms-${var.env}"
  location = var.region

  template {
    service_account = google_service_account.cloud_run.email

    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }

    # Cloud SQL connection via socket (no necesita IP pública)
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.db_connection_name]
      }
    }

    containers {
      # Imagen por DIGEST inmutable: garantía de que prod === staging
      image = "${var.image_repo}@${var.image_sha}"

      resources {
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
        cpu_idle = true
      }

      ports {
        container_port = 8080
      }

      env {
        name  = "ENV"
        value = var.env
      }
      env {
        name  = "DB_INSTANCE"
        value = var.db_connection_name
      }
      env {
        name  = "REDIS_HOST"
        value = var.redis_host
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = var.db_secret_id
            version = "latest"
          }
        }
      }

      # NOTA DE DISEÑO (agregado por el equipo): dos sondas con propósitos
      # distintos, ambas contra /healthz (el mismo endpoint que ya usa el
      # HEALTHCHECK nativo de Docker en el Dockerfile — Cloud Run no lee ese
      # HEALTHCHECK de Docker, tiene su propio mecanismo, por eso hace falta
      # declararlo aquí también).
      #
      # startup_probe: se ejecuta SOLO al arrancar un contenedor nuevo (cada
      # revisión nueva, cada instancia nueva al escalar). Mientras no pase,
      # Cloud Run NO envía tráfico real a esa instancia — evita mandar
      # peticiones de usuarios a un contenedor que aún está inicializando.
      startup_probe {
        http_get {
          path = "/healthz"
          port = 8080
        }
        initial_delay_seconds = 5    # tiempo antes del primer intento
        period_seconds         = 5    # cada cuánto reintenta
        timeout_seconds        = 3
        failure_threshold      = 6    # hasta 6 intentos (~35s) antes de darlo por fallido
      }

      # liveness_probe: se ejecuta de forma CONTINUA durante toda la vida de
      # la instancia (ya pasado el arranque). Si empieza a fallar de forma
      # repetida, Cloud Run reinicia el contenedor automáticamente, sin
      # intervención humana — el mecanismo técnico detrás de OPS-007
      # ("el sistema debe degradar suavemente, no requerir intervención
      # humana inmediata").
      liveness_probe {
        http_get {
          path = "/healthz"
          port = 8080
        }
        period_seconds    = 10
        timeout_seconds   = 3
        failure_threshold = 3
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }

    # VPC connector para alcanzar Memorystore (red privada) — recurso
    # google_vpc_access_connector definido arriba, justo después del
    # Service Account. "ALL_TRAFFIC" fuerza que TODO el tráfico saliente
    # del contenedor (no solo el destinado a rangos privados) pase por el
    # connector; se elige explícitamente porque, aunque Redis es el único
    # destino privado hoy, la salida general a internet ya la resuelve el
    # Cloud NAT del módulo network (Fase 1) sobre esta misma VPC.
    vpc_access {
      connector = google_vpc_access_connector.redis.id
      egress    = "ALL_TRAFFIC"
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  labels = var.labels

  lifecycle {
    ignore_changes = [
      # El image_sha lo controla el pipeline de despliegue, no terraform apply diario.
      # Si lo dejas sin ignore_changes, cada apply puede revertir un deploy reciente.
      template[0].containers[0].image,
    ]
  }
}

# ─── HTTPS Load Balancer + Cloud CDN ──────────────────────────────
# Estructura: serverless NEG → Backend Service → URL map → HTTPS proxy → Forwarding rule

resource "google_compute_region_network_endpoint_group" "cloud_run_neg" {
  name                  = "oms-${var.env}-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_run {
    service = google_cloud_run_v2_service.oms.name
  }
}

resource "google_compute_backend_service" "default" {
  name                  = "oms-${var.env}-backend"
  protocol              = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  enable_cdn            = true

  backend {
    group = google_compute_region_network_endpoint_group.cloud_run_neg.id
  }

  cdn_policy {
    cache_mode        = "CACHE_ALL_STATIC"
    default_ttl       = 3600
    max_ttl           = 86400
    negative_caching  = true
    serve_while_stale = 86400

    # NOTA DE DISEÑO (agregado por el equipo, corrección mínima de sintaxis
    # en la Fase 1 para desbloquear el parseo de toda la configuración raíz
    # — el diseño completo y afinado de la política de CDN se revisa en la
    # Fase 2 / bonus "Cloud CDN políticas finas"):
    # `cache_key_policy` es OBLIGATORIO en cdn_policy — define qué partes
    # de la URL usa el CDN para decidir si dos peticiones son "la misma"
    # y pueden compartir la misma respuesta cacheada.
    cache_key_policy {
      include_host         = true
      include_protocol     = true
      include_query_string = false   # provisional: se afinará en la Fase 2/bonus
    }
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_url_map" "default" {
  name            = "oms-${var.env}-url-map"
  default_service = google_compute_backend_service.default.id
}

# ─── Certificado SSL, proxy HTTPS y forwarding rule ───────────────
# NOTA DE DISEÑO (agregado por el equipo): un "Google-managed SSL
# certificate" es un certificado que Google emite y renueva automáticamente
# (a diferencia de gestionar tú mismo certificados o Let's Encrypt manual —
# ver CERTIFICADOS.md más adelante para esos escenarios). Requiere que el
# dominio indicado (var.lb_domain) tenga un registro DNS tipo A apuntando
# a la IP de `lb_ip` de abajo — sin eso, Google nunca puede completar la
# validación y el certificado se queda en estado "PROVISIONING" para siempre
# (no falla el `apply`, simplemente no llega nunca a "ACTIVE").
resource "google_compute_managed_ssl_certificate" "default" {
  name = "oms-${var.env}-cert"
  managed {
    domains = [var.lb_domain]
  }
}

# Target HTTPS Proxy: la pieza que efectivamente TERMINA la conexión TLS
# (descifra el tráfico HTTPS entrante) y consulta al url_map para decidir
# a qué backend reenviar la petición ya descifrada.
resource "google_compute_target_https_proxy" "default" {
  name             = "oms-${var.env}-https-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

resource "google_compute_global_address" "lb_ip" {
  name = "oms-${var.env}-lb-ip"
}

# Global Forwarding Rule: asocia la IP pública reservada (lb_ip) con el
# proxy HTTPS en el puerto 443 — es el "cable" final que conecta "esta IP
# pública" con "ese proxy"; sin esto, la IP reservada existe pero no está
# conectada a nada.
resource "google_compute_global_forwarding_rule" "https" {
  name                  = "oms-${var.env}-https-fr"
  ip_address            = google_compute_global_address.lb_ip.address
  port_range            = "443"
  target                = google_compute_target_https_proxy.default.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# ─── Outputs ──────────────────────────────────────────────────────
output "cloud_run_url"             { value = google_cloud_run_v2_service.oms.uri }
output "cloud_run_service_account" { value = google_service_account.cloud_run.email }
output "load_balancer_ip"          { value = google_compute_global_address.lb_ip.address }
