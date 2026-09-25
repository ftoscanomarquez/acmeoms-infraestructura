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
# Agregado por el equipo (Fase 7, bonus CMEK): mismo patrón que
# modules/database — nullable, permite operar sin CMEK.
variable "storage_cmek_key_id" {
  type    = string
  default = ""
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

  # ─── Política de CDN afinada (BONUS: Cloud CDN políticas finas) ────
  #
  # NOTA DE DISEÑO (agregado por el equipo, Fase 7): el diseño inicial
  # (Fase 1) dejaba TTLs fijos y `include_query_string = false` como
  # placeholder explícito, documentado como "provisional: se afinará en
  # el bonus". Este bloque es esa afinación real, con 3 decisiones
  # concretas que exige el bonus del enunciado (TTLs derivados de
  # headers, negative caching, cache por query string):
  cdn_policy {
    # USE_ORIGIN_HEADERS (en vez de CACHE_ALL_STATIC): el backend deja de
    # decidir por extensión de archivo qué cachear — respeta literalmente
    # los headers Cache-Control/Expires que la propia app emita en cada
    # respuesta. Es el mecanismo real detrás de "TTLs derivados de los
    # headers de la app" que pide el bonus: server.js (o el OMS real que
    # lo reemplace) es quien decide, respuesta por respuesta, si algo es
    # cacheable y por cuánto tiempo — no una regla genérica de Terraform
    # basada en la ruta o la extensión del archivo pedido.
    cache_mode = "USE_ORIGIN_HEADERS"

    # default_ttl/max_ttl/client_ttl NO aplican con USE_ORIGIN_HEADERS —
    # GCP los ignora activamente en este modo (documentado así por la
    # propia API) porque el origen ya manda esa información en cada
    # respuesta vía Cache-Control. Se omiten a propósito, no por olvido.

    # negative_caching: cachea también algunas respuestas de ERROR por un
    # tiempo corto — evita que un recurso que no existe golpee el backend
    # en cada petición repetida (ej. un bot escaneando rutas), sin afectar
    # el TTL de las respuestas 200 reales.
    #
    # HALLAZGO REAL (Fase 7, terraform apply real contra staging): un
    # primer intento incluía `code = 500` (asumiendo, por analogía con
    # otros CDNs, que cualquier código de error era válido aquí) — GCP lo
    # rechazó de verdad:
    #   Error 400: Invalid value for field
    #   'resource.cdnPolicy.negativeCachingPolicy[1].code': '500'.
    #   Valid options are [300, 301, 302, 307, 308, 404, 405, 410, 421,
    #   451, 501].
    # Es una lista CERRADA de códigos que Cloud CDN permite cachear como
    # negativos — 500 (error genérico del servidor) NO está permitido a
    # propósito: cachear agresivamente un error transitorio real (que
    # puede resolverse en el siguiente request) sería peligroso, a
    # diferencia de un 404/410 (recurso que realmente no existe) o un 501
    # (funcionalidad no implementada, tan estable como un 404). Se usa 501
    # en su lugar — mismo espíritu ("cachear errores estables, no
    # transitorios"), valor real aceptado por la API.
    negative_caching = true
    negative_caching_policy {
      code = 404
      ttl  = 30 # corto a propósito: si el recurso se crea después, no queremos servir el 404 cacheado por mucho tiempo
    }
    negative_caching_policy {
      code = 501
      ttl  = 10 # corto: si se despliega el código que implementa la funcionalidad, no queremos servir el 501 cacheado por mucho tiempo
    }

    # serve_while_stale: si el origen (Cloud Run) tarda o falla en
    # responder, el CDN puede seguir sirviendo la última copia válida
    # hasta por 1 día — mismo principio de "degradación suave" que
    # OPS-007 exige a nivel de aplicación (si Redis cae, la app sigue
    # respondiendo desde la DB), aplicado aquí a nivel de borde de red.
    serve_while_stale = 86400

    # HALLAZGO REAL (Fase 1, ver comentario original de este bloque):
    # cache_key_policy es OBLIGATORIO en cdn_policy — sin él, el `plan`
    # ni siquiera parsea. Ahora afinado de verdad: `include_query_string
    # = true` es la decisión correcta para una API/SPA real (a diferencia
    # del placeholder actual, que no tiene endpoints parametrizados por
    # query string) — sin esto, `/api/catalog/products?category=X` y
    # `/api/catalog/products?category=Y` compartirían la MISMA entrada de
    # caché, devolviendo contenido incorrecto a uno de los dos. Se
    # incluye TODO el query string (`query_string_whitelist` vacía = todo
    # el string se usa) porque hoy no hay un contrato de API real que
    # permita whitelistear parámetros concretos con seguridad — es la
    # opción conservadora y correcta mientras tanto.
    cache_key_policy {
      include_host           = true
      include_protocol       = true
      include_query_string   = true
      query_string_whitelist = []
    }
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# ─── Signed URLs para la SPA (BONUS: Cloud CDN políticas finas) ────
#
# NOTA DE DISEÑO (agregado por el equipo, Fase 7): el enunciado pide
# "signed URLs para SPA" — un mecanismo de Cloud CDN para servir
# contenido estático (el bundle de la SPA: JS/CSS/imágenes) solo a
# quien presente una URL firmada con expiración, en vez de dejar ese
# contenido público sin control. Requiere una CLAVE de firma asociada al
# backend service — se genera y se guarda en Secret Manager (mismo
# patrón que la password de Cloud SQL: nunca en texto plano en el
# código ni en el tfstate en claro).
#
# ALCANCE REAL DE ESTE PROYECTO (ver README.md, "Alcance explícito" y
# OBSERVABILIDAD.md): no existe todavía una SPA real que servir — el
# placeholder `server.js` es una API HTTP mínima, no una aplicación de
# frontend con assets estáticos. Se deja la CLAVE de firma y el binding
# ya creados y funcionales (verificable con `gcloud compute backend-services
# describe --format="value(cdnPolicy.signedUrlKeyNames)"`), documentando
# aquí el comando real para generar una URL firmada de prueba en cuanto
# exista contenido estático real que proteger:
#
#   gcloud compute sign-url "https://<dominio>/spa/index.html" \
#     --key-name=oms-<env>-spa-key \
#     --key-file=<ruta al valor del secreto de abajo> \
#     --expires-in=1h
resource "random_id" "spa_signing_key" {
  byte_length = 16 # Cloud CDN exige una clave de 16 bytes codificada en base64 URL-safe
}

resource "google_secret_manager_secret" "spa_signing_key" {
  secret_id = "oms-${var.env}-spa-signing-key"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
  labels = var.labels
}

resource "google_secret_manager_secret_version" "spa_signing_key" {
  secret      = google_secret_manager_secret.spa_signing_key.id
  secret_data = random_id.spa_signing_key.b64_url
}

resource "google_compute_backend_service_signed_url_key" "spa" {
  name            = "oms-${var.env}-spa-key"
  backend_service = google_compute_backend_service.default.name
  key_value       = random_id.spa_signing_key.b64_url
}

# ─── Bucket de assets/SPA con CMEK (BONUS: CMEK propia) ────────────
# NOTA DE DISEÑO (agregado por el equipo, Fase 7): "aplicada a Cloud SQL
# y a un bucket" (enunciado, sección 6). Este es ese bucket — el mismo
# que serviría el bundle estático de la SPA que las signed URLs de arriba
# protegen (arquitectura objetivo del enunciado, sección 2: "Cloud
# Storage + Cloud CDN" para "Object storage / SPA"). No existía ningún
# bucket de aplicación en este proyecto hasta este bonus — se crea aquí,
# no en modules/database, porque conceptualmente pertenece a la capa de
# cómputo/entrega de contenido, junto al resto de piezas del CDN.
resource "google_storage_bucket" "spa_assets" {
  name          = "${var.project_id}-oms-${var.env}-spa"
  location      = var.region
  storage_class = "STANDARD"

  uniform_bucket_level_access = true # sin ACLs heredadas por objeto — mismo estándar que los buckets de tfstate (Fase 0)

  # HALLAZGO REAL (Fase 7, ver terraform plan real durante la verificación
  # de este bonus): a diferencia de `encryption_key_name` en Cloud SQL (un
  # simple string que sí acepta `null`), el bloque `encryption` de
  # google_storage_bucket EXIGE que `default_kms_key_name` tenga un valor
  # si el bloque existe — el provider rechaza el plan con "Missing required
  # argument" al intentar pasar `null` condicionalmente ahí dentro. La
  # forma correcta de "bucket con o sin CMEK, según una variable" es un
  # bloque `dynamic`: con storage_cmek_key_id="" (enable_cmek=false), el
  # `for_each` itera 0 veces y el bloque `encryption` NI SIQUIERA SE
  # DECLARA — el bucket queda cifrado con la clave default de Google
  # (comportamiento normal), no con un `null` inválido.
  dynamic "encryption" {
    for_each = var.storage_cmek_key_id != "" ? [var.storage_cmek_key_id] : []
    content {
      default_kms_key_name = encryption.value
    }
  }

  versioning {
    enabled = true # protección básica ante un borrado/sobrescritura accidental del bundle de la SPA
  }

  labels = var.labels

  lifecycle {
    prevent_destroy = true
  }
}

output "spa_assets_bucket_name" {
  value       = google_storage_bucket.spa_assets.name
  description = "Bucket de assets/SPA, cifrado con CMEK propia (bonus) y protegido por las signed URLs de Cloud CDN (bonus)."
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

# Agregado por el equipo (Fase 7, bonus Cloud CDN): nombre del secreto
# que guarda la clave de firma de URLs — quien necesite generar una URL
# firmada real (`gcloud compute sign-url`) la lee de aquí, nunca del
# código ni del tfstate en texto plano.
output "spa_signing_key_secret_id" {
  value       = google_secret_manager_secret.spa_signing_key.secret_id
  description = "ID del secreto en Secret Manager con la clave de firma de URLs de Cloud CDN (bonus: signed URLs para SPA)."
}
