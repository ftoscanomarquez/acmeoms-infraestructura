# ── Módulo: NETWORK ────────────────────────────────────────────────
# Provisiona la VPC privada con dos subredes en zonas distintas (NFR-AVAIL-001).
# Sin IPs públicas en compute: salida a internet vía Cloud NAT.

variable "project_id" { type = string }
variable "region"     { type = string }
variable "env"        { type = string }
variable "vpc_cidr"   { type = string }
variable "labels"     { type = map(string) }

# ─── VPC ──────────────────────────────────────────────────────────
resource "google_compute_network" "main" {
  name                    = "oms-${var.env}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# ─── Subred privada para Cloud SQL / Memorystore / Cloud Run ──
#
# NOTA DE DISEÑO (agregado por el equipo, no venía en el esqueleto original):
# el TODO original pedía "dos subredes en al menos dos zonas". En GCP una
# subred NO está atada a una sola zona: abarca automáticamente TODAS las
# zonas de la región indicada en `region` (a diferencia de AWS, donde una
# subred sí vive en una única zona). Por eso NFR-AVAIL-001 (multi-zona) ya
# queda cubierto con una sola subred por `region`, sin necesidad de
# duplicarla — de hecho, más adelante `google_sql_database_instance` con
# `availability_type = "REGIONAL"` (módulo database) reparte réplicas entre
# zonas usando esta misma subred, sin que el módulo network tenga que saber
# nada de zonas concretas.
#
# La interpretación correcta y útil de "más de una subred" aquí es la
# SEGMENTACIÓN por propósito (separar tráfico por función, no por ubicación
# física): se añade una segunda subred `connector`, reservada para el VPC
# Access Connector que Cloud Run necesitará en la Fase 2 para poder hablar
# con Memorystore Redis por IP privada. Tenerla separada de `private` deja
# preparado un firewall más granular si en el futuro se quiere restringir
# el tráfico del connector de forma distinta al resto.
resource "google_compute_subnetwork" "private" {
  name                     = "oms-${var.env}-private"
  ip_cidr_range            = cidrsubnet(var.vpc_cidr, 4, 0)  # /20 del /16 → 10.20.0.0/20 (4.096 IPs)
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true   # acceso a APIs de Google sin salir a internet
}

# ─── Subred para el VPC Access Connector (Cloud Run → Redis privado) ──
# Mismo tamaño que `private` (/20) por simplicidad, aunque un connector
# real solo necesita un puñado de IPs — se prioriza consistencia sobre
# optimizar el espacio de direcciones (que aquí sobra de todos modos:
# el /16 completo tiene 65.536 IPs, y solo usamos 2 × 4.096 = 8.192).
#
# El índice "1" (en vez de "0", que ya usa `private`) es lo que garantiza
# que este bloque NO se solape con el anterior: cidrsubnet(vpc_cidr, 4, N)
# corta el /16 en 16 franjas iguales de /20, y cada índice N (0 a 15)
# selecciona una franja distinta y disjunta de las demás. Índice 1 da
# 10.20.16.0/20 — justo la franja siguiente a la que ya ocupa `private`
# (10.20.0.0/20), sin ningún hueco ni superposición entre ambas.
resource "google_compute_subnetwork" "connector" {
  name                     = "oms-${var.env}-connector"
  ip_cidr_range            = cidrsubnet(var.vpc_cidr, 4, 1)  # /20 del /16 → 10.20.16.0/20
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true
}

# ─── Private Service Connect para Cloud SQL ───────────────────
# Cloud SQL necesita un rango privado reservado para crear su endpoint.
resource "google_compute_global_address" "private_service_range" {
  name          = "oms-${var.env}-sql-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
}

# ─── Cloud NAT para salida a internet (instancias sin IP pública) ──
#
# NOTA DE DISEÑO (agregado por el equipo): ningún recurso de este proyecto
# tiene IP pública (Cloud SQL, Redis y las subredes de arriba son todas
# privadas). Una IP privada (ej. 10.20.0.5) no significa nada fuera de esta
# VPC — internet solo enruta usando IPs públicas, únicas en el mundo. Si
# algo dentro de la VPC necesita iniciar una conexión saliente a internet
# (ej. Cloud Run llamando a una API externa que no sea de Google, o una VM
# descargando paquetes del sistema operativo), necesita un NAT: un
# intermediario que traduce esa IP privada a una IP pública propia del NAT
# para el viaje de ida, y sabe devolver la respuesta a quien la pidió sin
# que la VM privada quede nunca expuesta o alcanzable desde fuera (es
# tráfico de un solo sentido: sale, y solo vuelve la respuesta a lo que se
# pidió — nadie puede iniciar una conexión ENTRANTE hacia la VM por aquí).
#
# En GCP, Cloud NAT siempre se configura como una extensión de un Cloud
# Router (no existe como recurso independiente) — por eso son dos recursos:
resource "google_compute_router" "main" {
  name    = "oms-${var.env}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  name   = "oms-${var.env}-nat"
  router = google_compute_router.main.name
  region = var.region

  # AUTO_ONLY: Google asigna automáticamente las IPs públicas que el NAT
  # necesite para hacer la traducción. La alternativa (MANUAL_ONLY) obligaría
  # a reservar IPs públicas fijas a mano — más control, pero coste y trabajo
  # extra que no se justifica en este proyecto (no hay motivo para necesitar
  # una IP de salida fija/predecible).
  nat_ip_allocate_option = "AUTO_ONLY"

  # Aplica el NAT a TODAS las subredes de esta VPC (private y connector),
  # en vez de listarlas una por una — evita que una futura subred nueva
  # se quede sin salida a internet por olvido de actualizar esta lista.
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"   # registra solo conexiones NAT fallidas (falta de puertos/IPs), útil para diagnosticar sin generar ruido de logs por cada conexión exitosa
  }
}

# ─── Firewall: deny-all por defecto + reglas explícitas ───────────
#
# NOTA DE DISEÑO (agregado por el equipo): cualquier VPC en modo custom
# (auto_create_subnetworks = false, como la nuestra) ya aplica DOS reglas
# implícitas de fábrica, sin que se escriba nada: (1) deniega TODO el
# tráfico entrante, desde cualquier origen — incluso desde dentro de la
# propia VPC; (2) permite TODO el tráfico saliente. Es la postura correcta
# de seguridad ("todo cerrado, abre solo lo que necesites"). Las 3 reglas
# de abajo son EXCEPCIONES explícitas sobre ese "todo cerrado" — cada una
# abre un agujero puntual y controlado, nunca al revés.

# Regla 1 · Tráfico interno dentro de la propia VPC.
# Sin esto, dos recursos nuestros (ej. Cloud Run → Redis) NO podrían
# hablarse entre sí aunque vivan en la misma VPC: el deny-all de entrada
# aplica también al tráfico que viene de dentro de la propia red.
resource "google_compute_firewall" "allow_internal" {
  name    = "oms-${var.env}-allow-internal"
  network = google_compute_network.main.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"   # permite ping / diagnóstico de red entre recursos internos
  }

  source_ranges = [var.vpc_cidr]   # 10.20.0.0/16 — toda la VPC, cubre private y connector
}

# Regla 2 · SSH vía IAP (Identity-Aware Proxy), para el bastion del bonus.
# IAP permite hacer SSH a una VM SIN que tenga IP pública ni el puerto 22
# expuesto a internet: en vez de conectarse directo a la VM, el cliente se
# conecta a un proxy de Google (autenticado con IAM), y ese proxy reenvía
# la conexión internamente. Google publica un rango de IPs FIJO y
# documentado desde el que sale ese tráfico (35.235.240.0/20) — no es un
# valor inventado, es el estándar oficial para este mecanismo. La regla
# solo aplica a VMs marcadas explícitamente con la etiqueta de red
# "iap-ssh" (target_tags), así que hoy no afecta a ningún recurso — queda
# lista para cuando se implemente el bastion en la Fase 7.
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "oms-${var.env}-allow-iap-ssh"
  network = google_compute_network.main.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]   # rango oficial de IAP (Google)
  target_tags   = ["iap-ssh"]
}

# Regla 3 · Health checks del Load Balancer hacia Cloud Run (puerto 8080).
# El Load Balancer (Fase 2) verifica constantemente que el servicio está
# vivo enviando peticiones HTTP periódicas al puerto de la app. Esas
# peticiones salen de rangos de IP fijos que pertenecen al GFE (Google
# Front End, la capa interna que enruta el tráfico de los balanceadores
# de Google) — dos rangos oficiales documentados, no inventados:
# 130.211.0.0/22 y 35.191.0.0/16. Sin esta regla, el Load Balancer
# marcaría el servicio como "caído" (sus propios chequeos de salud
# quedarían bloqueados por el deny-all) y dejaría de enviarle tráfico real.
resource "google_compute_firewall" "allow_lb_health_checks" {
  name    = "oms-${var.env}-allow-lb-health-checks"
  network = google_compute_network.main.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]   # rangos oficiales de GFE (Google)
}

# ─── Outputs ──────────────────────────────────────────────────────
output "network_id"          { value = google_compute_network.main.id }
output "network_self_link"   { value = google_compute_network.main.self_link }
output "private_subnet_id"   { value = google_compute_subnetwork.private.id }
output "private_subnet_cidr" { value = google_compute_subnetwork.private.ip_cidr_range }
# Agregado por el equipo: la Fase 2 (módulo compute) necesita esta subred
# para crear el VPC Access Connector de Cloud Run.
output "connector_subnet_id"   { value = google_compute_subnetwork.connector.id }
output "connector_subnet_cidr" { value = google_compute_subnetwork.connector.ip_cidr_range }
