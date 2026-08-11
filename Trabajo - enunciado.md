# ⚠️⚠️⚠️  ¡ATENCIÓN — LEE ESTO ANTES DE EMPEZAR!  ⚠️⚠️⚠️
# 👉 EL DOMINIO DE TU ENTREGA ES: **OMS (AcmeOMS)** 👈
# ❌ ¡NO entregues otro sistema! Cualquier otro dominio que aparezca aquí es SOLO ejemplo de referencia del equipo docente.
# ℹ️ Cada bloque ALTERNA el dominio a propósito: es parte del aprendizaje, aplicar los conceptos a un dominio distinto (como en el trabajo real).

---

# Trabajo final — Bloque 4 · Plataforma e infraestructura

## 1 · Contexto

Eres parte del equipo de plataforma de **AcmeOMS**, un SaaS que gestiona pedidos para tiendas online. El documento de arquitectura del sistema (lo tienes en el material del curso, `03-arquitectura.md`) describe el OMS como un **monolito modular** desplegado en dos regiones, con seis bounded contexts (Catalog, Inventory, Orders, Payments, Billing, IAM), persistencia en PostgreSQL multi-AZ, caché en Redis, y pagos delegados a Stripe.

**Tu trabajo en este bloque NO es implementar la aplicación** —eso vendrá en bloques posteriores—. **Tu trabajo es provisionar y operar la infraestructura** que la va a alojar. Para esto vas a usar todo lo que aprendiste en los cinco vídeos: Docker, Cloud (GCP), Terraform, CI/CD avanzado y Ansible.

### Una decisión que tomamos por ti: GCP en lugar de AWS

El documento de arquitectura original menciona AWS (RDS, ElastiCache, ECS/EKS, CloudFront). Para mantener coherencia con el bloque, **vas a implementar la versión equivalente en Google Cloud Platform**. El mapeo de servicios queda así:

| Concepto | Equivalente AWS (doc original) | Equivalente GCP (tu trabajo) |
|---|---|---|
| Base de datos relacional managed | RDS PostgreSQL | Cloud SQL PostgreSQL |
| Caché en memoria | ElastiCache Redis | Memorystore Redis |
| Contenedores managed | ECS / EKS | Cloud Run (o GKE Autopilot opcional) |
| Object storage / SPA | S3 + CloudFront | Cloud Storage + Cloud CDN |
| Secretos | Secrets Manager | Secret Manager |
| IAM federada para CI/CD | OIDC + IAM Role | Workload Identity Federation |

La arquitectura lógica y las restricciones (NFRs, OPS, REG) **NO cambian**. Solo cambia la implementación.

---

## 2 · Objetivo

Construir, con **Terraform** y **Ansible**, un subconjunto operativo de la plataforma del OMS sobre Google Cloud que cumpla la spec original y que pueda desplegarse en dos entornos —staging y producción— con el mismo binario.

### Arquitectura objetivo (subset realista)

```
                    ┌─────────────────────┐
                    │   USUARIOS FINALES  │
                    └──────────┬──────────┘
                               │ HTTPS (TLS 1.3)
                               ▼
                    ┌─────────────────────┐
                    │ HTTPS Load Balancer │  ← Cloud LB + Cloud CDN
                    │      + WAF          │
                    └──────────┬──────────┘
                               │
                  ┌────────────┼─────────────┐
                  │            │             │
                  ▼            ▼             ▼
              ┌──────────────────────────────────┐
              │  Cloud Run — OMS app             │  ← stateless, autoescalado
              │  (contenedor del monolito)       │     (NFR-SCAL-001)
              └────────┬─────────────────┬───────┘
                       │                 │
                       ▼                 ▼
              ┌─────────────┐  ┌──────────────────┐
              │ Memorystore │  │   Cloud SQL      │  ← multi-zone HA
              │   Redis     │  │   PostgreSQL     │     (NFR-AVAIL-001)
              │  (caché)    │  │                  │     (OPS-005 backups)
              └─────────────┘  └──────────────────┘
                                        │
                                        ▼
                              ┌──────────────────┐
                              │ Cloud Storage    │  ← static SPA + backups
                              │ (SPA + assets)   │
                              └──────────────────┘

                  Todo dentro de una VPC privada
                  región: europe-west3 (Frankfurt) — REG-GDPR-001
                  secretos: Secret Manager
                  CI/CD: GitHub Actions con Workload Identity Federation
```

---

## 3 · Restricciones de la spec que tienes que cumplir

Las que están escritas en `01-inventario-restricciones.md` del proyecto original. Para tu trabajo, son **innegociables**:

### Cumplimiento regulatorio
- **REG-GDPR-001** — Despliegue solo en regiones europeas (`europe-west3` obligatoria; `europe-central2` opcional para el bonus DR)
- **REG-GDPR-003** — Audit trail inmutable: Cloud Logging con sink a un bucket de retención larga
- **REG-PCI-001** — Cero datos de tarjeta tocando tu infra (Stripe queda fuera de scope)

### No funcionales
- **NFR-AVAIL-001** — Multi-zone con failover automático (Cloud SQL con `availability_type = "REGIONAL"`)
- **NFR-SEC-001** — Encriptación en reposo (CMEK opcional para bonus; AES-256 por defecto obligatorio)
- **NFR-SEC-002** — TLS 1.3 en el Load Balancer
- **NFR-SCAL-001** — Autoescalado horizontal hasta 5× el pico medido (`max_instance_count` en Cloud Run)
- **NFR-PERF-001** — Caché Redis delante del catálogo

### Operativas
- **OPS-005** — Backups con Point-In-Time Recovery 14 días; un ejercicio de restauración mensual en staging (no implementas el ejercicio, solo dejas el comando documentado en runbook)
- **OPS-007** — Sistema degrada suavemente: si Redis cae, la app sigue respondiendo desde la DB

### Operativas que aprendiste en el bloque
- **Cero credenciales estáticas** en el repo o en variables de CI (Vídeo 4)
- **Mismo `image_sha`** en staging y producción (Vídeo 5)
- **Idempotencia** en todos los playbooks (Vídeo 5)
- **`terraform plan` limpio** antes de cualquier `apply` (Vídeo 3)
- **`deletion_protection = true`** + `lifecycle { prevent_destroy = true }` en la base de datos (Vídeo 3)

---

## 4 · Entregables

Entregas un repo Git con la estructura que viene en este esqueleto. Cada `TODO` que encuentres es tuyo de rellenar.

```
oms-platform/
├── README.md                              ← descripción y cómo arrancar
├── Trabajo - enunciado.md                 ← este documento (no se modifica)
├── .gitignore
│
├── docker/
│   └── Dockerfile                         ← multi-stage; cumple la spec del Vídeo 1
│
├── terraform/
│   ├── versions.tf                        ← lock de providers
│   ├── variables.tf                       ← variables del módulo raíz
│   ├── main.tf                            ← composición de los 4 módulos
│   ├── outputs.tf                         ← outputs útiles (LB IP, DB connection)
│   ├── envs/
│   │   ├── staging.tfvars                 ← valores para staging
│   │   └── production.tfvars              ← valores para producción
│   └── modules/
│       ├── network/main.tf                ← VPC, subredes, firewall
│       ├── database/main.tf               ← Cloud SQL + Memorystore Redis
│       ├── compute/main.tf                ← Cloud Run + Load Balancer + CDN
│       └── iam/main.tf                    ← Service Accounts + WIF
│
├── ansible/
│   ├── ansible.cfg
│   ├── requirements.yml                   ← colecciones: google.cloud
│   ├── inventory/gcp.yml                  ← inventario dinámico (bonus bastion)
│   ├── group_vars/
│   │   ├── all.yml                        ← lo común a todos los entornos
│   │   ├── staging.yml                    ← diferencias legítimas (capacidad, endpoints)
│   │   └── production.yml                 ← idem
│   ├── playbooks/
│   │   ├── deploy.yml                     ← despliega `image_sha` al entorno
│   │   └── rollback.yml                   ← rollback a la revisión anterior
│   └── roles/oms_cloud_run/
│       └── tasks/main.yml                 ← lógica idempotente del despliegue
│
└── .github/workflows/
    └── ci-cd.yml                          ← matriz + build + WIF + promote
```

### Lo que tiene que pasar para que se considere terminado

| Comando | Qué debe pasar |
|---|---|
| `terraform init && terraform plan -var-file=envs/staging.tfvars` | Plan limpio, sin errores |
| `terraform apply -var-file=envs/staging.tfvars` | Crea toda la infra de staging en GCP |
| `terraform plan -var-file=envs/staging.tfvars` (segunda vez) | "No changes" — confirmación de que es idempotente |
| `ansible-playbook playbooks/deploy.yml -e env=staging -e image_sha=sha256:...` | Despliega esa imagen a Cloud Run staging |
| Repetir el playbook | `changed=0` — idempotencia |
| `ansible-playbook playbooks/deploy.yml -e env=production -e image_sha=sha256:...` | Misma imagen va a producción |
| Push a `main` con tag `v1.0.0` | El workflow construye, prueba, firma y despliega vía WIF |

---

## 5 · Rúbrica de evaluación (100 puntos)

| Bloque | Pts | Criterio |
|---|---|---|
| **Estructura Terraform** | 15 | Módulos bien delimitados; variables tipadas con descripción; outputs útiles; `versions.tf` con providers fijados a versión menor. |
| **Implementación recursos GCP** | 25 | VPC con subredes en al menos 2 zonas; Cloud SQL `REGIONAL` con PITR; Memorystore Redis Standard; Cloud Run con autoscaling; Load Balancer con CDN; Secret Manager con bindings. |
| **Plan limpio + idempotencia** | 10 | `terraform plan` no muestra cambios en segunda ejecución; sin warnings. |
| **Protecciones de producción** | 10 | `deletion_protection`, `prevent_destroy`, `backup_configuration` con PITR ≥ 14d, `database_version` pinneada. |
| **Ansible deploy idempotente** | 15 | Playbook devuelve `changed=0` en segunda ejecución; usa módulos `google.cloud.gcp_cloudrun_*` (no shell directo); maneja la revisión y el switch de tráfico. |
| **Diferencias staging/prod** | 10 | `diff group_vars/staging.yml group_vars/production.yml` muestra solo capacidad/endpoints — nada de comportamiento. Defendible con una línea por diferencia. |
| **CI/CD con WIF (sin claves)** | 10 | Workflow con `permissions: id-token: write`, sin `GCP_SA_KEY_JSON` en `secrets`. Trust policy con `attribute.repository` constraint. |
| **README + decisiones** | 5 | README claro con cómo arrancar; sección "Decisiones" explicando los 3 trade-offs principales que tomaste. |

**Penalizaciones:**
- −20 pts si hay alguna credencial estática en el repo (las pillamos con `gitleaks`)
- −10 pts si la imagen desplegada en `production` NO es el mismo SHA que la de `staging`
- −5 pts por cada `terraform apply` que rompa producción en el entorno de evaluación

---

## 6 · Bonus opcionales (sumas sobre la nota)

| Bonus | Pts | Qué implica |
|---|---|---|
| Multi-region DR | +10 | Replica de Cloud SQL en `europe-central2` + runbook documentado de failover |
| Cloud CDN con políticas finas | +5 | Cache TTLs derivados de los headers de la app; negative caching; signed URLs para SPA |
| Bastion VM con Ansible | +10 | Una Compute Engine con `Datadog` agent vía role Ansible; inventario dinámico la descubre por label `role=bastion` |
| CMEK propia | +5 | Clave KMS gestionada por ti en lugar de la default de Google, aplicada a Cloud SQL y a un bucket |
| Migración expand-and-contract | +5 | Documentas (no implementas) el flujo para hacer un cambio destructivo de schema sin downtime |

---

## 7 · Referencias del bloque

Cada parte del trabajo se apoya en un vídeo concreto. Si te bloqueas, vuelve aquí.

| Tarea | Vídeo que te ayuda |
|---|---|
| Escribir el Dockerfile del OMS | **Vídeo 1** — multi-stage, no-root, healthcheck, labels OCI |
| Decidir entre Cloud Run y GKE | **Vídeo 2** — managed vs self-managed, modelo de coste |
| Estructurar Terraform en módulos | **Vídeo 3** — modules, envs, plan-apply, defensas de producción |
| Configurar WIF en GitHub Actions | **Vídeo 4** — Workload Identity Federation, secretos efímeros |
| Diferenciar entornos sin reconstruir | **Vídeo 5** — group_vars, mismo SHA, idempotencia |

Y los temarios detallados con código de ejemplo:

- `Temario detallado – Bloque 4 · Plataforma e infraestructura.md`
- `Guion completo – Bloque 4 · Plataforma e infraestructura.md`

---

## 8 · Política de uso de IA

**Permitido y recomendado:** usar Claude, Copilot, Gemini o cualquier otro asistente para generar borradores de Terraform y Ansible.

**Obligatorio:** documentar en el README, en la sección "Decisiones", los **3 cambios concretos** que hiciste al borrador de la IA antes de aprobar el código. Igual que vimos en el Vídeo 3 con el ejemplo de Cloud SQL.

Trabajar con IA está bien. Aplicar lo que sale sin revisar, no.

---

## 9 · Cómo entregar

1. Clona este esqueleto en un repo privado tuyo (GitHub, GitLab, lo que prefieras)
2. Completa todos los `TODO` (busca `TODO:` en todos los ficheros con `grep -r TODO`)
3. Verifica que los 7 comandos de la sección 4 funcionan
4. Comparte el repo con el correo del instructor
5. Tag de release `v1.0.0` apuntando al commit final

**Fecha límite:** 2 semanas desde que recibes el enunciado.

**Dudas:** canal `#trabajo-modulo-1` de Slack. Estamos para ayudar a desbloquear, no para resolver el ejercicio.

¡Adelante!
