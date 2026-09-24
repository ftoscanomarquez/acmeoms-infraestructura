# ── Módulo: COMPUTE ───────────────────────────────────────────────
# Cloud Run para el monolito OMS + HTTPS Load Balancer + Cloud CDN.
# Cloud Run es stateless: NFR-SCAL-001 (autoescalado horizontal hasta 5×).

variable "project_id" { type = string }
variable "region" { type = string }
variable "env" { type = string }
variable "image_repo" { type = string }
variable "image_sha" { type = string }
variable "cloud_run_min_instances" { type = number }
variable "cloud_run_max_instances" { type = number }
# HALLAZGO REAL (Fase 5): cpu/memory estaban hardcodeados aquí abajo
# ("1000m"/"2Gi" fijos para AMBOS entornos), mientras que
# ansible/group_vars/production.yml pedía 2000m — Ansible intentaba "subir"
# una CPU que Terraform ya había fijado en 1000m, y la suma de ambas
# revisiones coexistiendo (la vieja de Terraform + la nueva de Ansible)
# excedía la cuota CpuAllocPerProjectRegion. Se parametriza para que
# Terraform sea la única fuente de verdad de la "forma" del contenedor
# (principio ya aplicado a min/max_instances) y Ansible solo compare
# contra estos mismos valores, nunca los cambie por su cuenta.
variable "cloud_run_cpu" { type = string }
variable "cloud_run_memory" { type = string }
variable "db_connection_name" { type = string }
variable "db_secret_id" { type = string }
variable "redis_host" { type = string }
variable "labels" { type = map(string) }
# Agregado por el equipo: subred dedicada (preparada en el módulo network,
# Fase 1) para el VPC Access Connector que permite a Cloud Run alcanzar
# Memorystore Redis por IP privada. Se necesitan DOS formas del mismo
# recurso porque distintos campos de GCP esperan formatos distintos:
# `connector_subnet_id` (ruta completa, sin uso actual pero se deja
# disponible para otros posibles usos futuros) y `connector_subnet_name`
# (nombre corto, el que realmente exige `google_vpc_access_connector`).
variable "connector_subnet_id" { type = string }
variable "connector_subnet_name" { type = string }
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
  type = string
  # En minúsculas a propósito: GCP normaliza automáticamente el campo
  # `domains` de un certificado managed a minúsculas al crearlo. Si aquí se
  # escribe con mayúsculas, Terraform detecta una diferencia permanente
  # entre "lo que pedimos" y "lo que GCP realmente guardó", y como ese
  # campo es inmutable, fuerza destruir y recrear el certificado en CADA
  # apply (visto en la práctica durante la Fase 2 de este proyecto).
  default = "pendiente-dominio-real.example.com"
}

# ─── Repositorio de Artifact Registry (imágenes Docker del OMS) ───
# NOTA DE DISEÑO (agregado por el equipo, corrección de un hallazgo real
# durante la Fase 2/3): este repositorio se había creado inicialmente a
# mano vía `gcloud artifacts repositories create`, fuera de Terraform. Eso
# es incorrecto por dos razones: (1) Terraform nunca lo conocería, así que
# un futuro `terraform destroy` lo dejaría huérfano, generando coste
# indefinidamente sin que el proyecto lo controle; (2) rompe la
# reproducibilidad — recrear el proyecto desde cero requeriría acordarse
# de este paso manual aparte, contradiciendo el principio de
# Infraestructura como Código que exige el enunciado. Se revirtió el
# recurso creado a mano y se define aquí correctamente.
resource "google_artifact_registry_repository" "oms" {
  location      = var.region
  repository_id = "oms"
  format        = "DOCKER"
  description   = "Repositorio de imágenes Docker del OMS (AcmeOMS)."
  labels        = var.labels
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
  name   = "oms-${var.env}-connector"
  region = var.region
  subnet {
    # NOTA DE DISEÑO (hallazgo real durante el apply de la Fase 2): el
    # campo `subnet.name` de este recurso espera el NOMBRE CORTO de la
    # subred (ej. "oms-staging-connector"), no la ruta completa que
    # devuelve el atributo `.id` de una subred (algo como
    # ".../regions/europe-west3/subnetworks/oms-staging-connector").
    # Es una inconsistencia real entre recursos de GCP: unos esperan `.id`
    # completo, otros solo `.name` corto — aquí hay que usar `.name`.
    name = var.connector_subnet_name
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
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
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
      # distintos, ambas contra /health (el mismo endpoint que ya usa el
      # HEALTHCHECK nativo de Docker en el Dockerfile — Cloud Run no lee ese
      # HEALTHCHECK de Docker, tiene su propio mecanismo, por eso hace falta
      # declararlo aquí también).
      #
      # CORRECCIÓN REAL (hallazgo durante el primer despliegue, Fase 2): el
      # endpoint originalmente se llamaba /healthz. Aunque estas probes
      # INTERNAS de Cloud Run sí pasaron correctamente contra /healthz (el
      # servicio llegó a status.conditions Ready=True), el tráfico PÚBLICO
      # externo a esa misma ruta era interceptado por Google Front End
      # (GFE) antes de llegar al contenedor, devolviendo un 404 genérico de
      # Google sin que la petición apareciera nunca en los logs de Cloud
      # Run. Se estandarizó a /health en todo el proyecto (server.js,
      # Dockerfile, y aquí) para evitar cualquier ambigüedad entre el
      # comportamiento de las probes internas y el del tráfico público real.
      #
      # startup_probe: se ejecuta SOLO al arrancar un contenedor nuevo (cada
      # revisión nueva, cada instancia nueva al escalar). Mientras no pase,
      # Cloud Run NO envía tráfico real a esa instancia — evita mandar
      # peticiones de usuarios a un contenedor que aún está inicializando.
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 5 # tiempo antes del primer intento
        period_seconds        = 5 # cada cuánto reintenta
        timeout_seconds       = 3
        failure_threshold     = 6 # hasta 6 intentos (~35s) antes de darlo por fallido
      }

      # liveness_probe: se ejecuta de forma CONTINUA durante toda la vida de
      # la instancia (ya pasado el arranque). Si empieza a fallar de forma
      # repetida, Cloud Run reinicia el contenedor automáticamente, sin
      # intervención humana — el mecanismo técnico detrás de OPS-007
      # ("el sistema debe degradar suavemente, no requerir intervención
      # humana inmediata").
      liveness_probe {
        http_get {
          path = "/health"
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
      # HALLAZGO REAL (Fase 5): sin esto, cada `terraform apply` posterior a
      # un despliegue de Ansible revertía `traffic` a su forma declarativa
      # pura (100% a la revisión "LATEST", sin `client`/`revision` fijados),
      # deshaciendo el control fino de canary/tag que Ansible acaba de
      # asignar con `gcloud run services update-traffic`. Mismo principio
      # que con la imagen: Terraform declara la FORMA inicial (el "molde"),
      # pero quién sirve qué % de tráfico es responsabilidad exclusiva del
      # pipeline de despliegue una vez el servicio ya existe.
      traffic,
      # `client`/`client_version`: metadata que `gcloud run deploy` escribe
      # automáticamente en cada despliegue de Ansible (identifica qué
      # herramienta hizo el último cambio) — Terraform no la fija a
      # propósito y no debe disputarla en cada apply posterior.
      client,
      client_version,
      # `template[0].revision`: nombre autogenerado de la revisión activa
      # (ej. "oms-staging-00010-zor") — cambia en cada deploy de Ansible,
      # Terraform nunca lo declara ni debe intentar "vaciarlo" de vuelta.
      template[0].revision,
    ]
  }
}

# ─── Permiso de invocación pública ─────────────────────────────────
# NOTA DE DISEÑO (agregado por el equipo, hallazgo real tras el primer
# despliegue): por defecto, Cloud Run NO permite invocar el servicio sin
# autenticación — la política IAM nace vacía (`gcloud run services
# get-iam-policy` devolvía sin ningún binding). Al probar la URL nativa de
# Cloud Run, esto se manifestó como 403/404 devueltos por la capa de Google
# Front End (IAM), ANTES de que la petición llegara al contenedor — el
# servicio en sí ya estaba sano (`status.conditions: Ready = True`).
#
# Se otorga `roles/run.invoker` a `allUsers` porque este es un servicio
# HTTP público destinado a recibir tráfico de clientes finales a través del
# Load Balancer (arquitectura objetivo del enunciado) — no es un servicio
# interno. El acceso real de los usuarios finales sigue pasando por HTTPS
# vía el Load Balancer; este binding solo habilita que Cloud Run ACEPTE
# esas peticiones en lugar de rechazarlas por falta de autenticación.
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.oms.name
  role     = "roles/run.invoker"
  member   = "allUsers"
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
      include_query_string = false # provisional: se afinará en la Fase 2/bonus
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
output "cloud_run_url" { value = google_cloud_run_v2_service.oms.uri }
output "cloud_run_service_account" { value = google_service_account.cloud_run.email }
output "load_balancer_ip" { value = google_compute_global_address.lb_ip.address }
# Agregado por el equipo: URL completa del repositorio de Artifact Registry,
# útil para el pipeline de CI/CD (Fase 6) al hacer `docker push`.
output "artifact_registry_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.oms.repository_id}"
}
