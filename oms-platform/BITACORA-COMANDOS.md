# Bitácora de comandos — OMS Platform (AcmeOMS)

> **Propósito:** registro cronológico de cada comando ejecutado durante la construcción de esta infraestructura: qué hace, por qué se ejecutó en ese momento, qué salida se esperaba/obtuvo, y qué se hizo si falló. La idea es que cualquier persona (incluido tú mismo dentro de unos meses) pueda **reproducir todo el proceso a mano**, sin depender de esta sesión de Claude Code.
>
> **Convención de cada entrada:**
> - **Contexto**: en qué fase estamos y por qué se ejecuta esto ahora.
> - **Comando**: el comando exacto.
> - **Qué hace**: explicación de cada flag/parte relevante.
> - **Resultado esperado / obtenido**: qué debía pasar y qué pasó.
> - **Hallazgos/errores**: si algo falló, qué fue y cómo se solucionó.

Ver también [`../PROGRESO.md`](../PROGRESO.md) para el estado general por fases.

---

## Índice de fases

- [Fase 0 — Cuentas, accesos y doble remoto](#fase-0--cuentas-accesos-y-doble-remoto)
- Fase 1 — Terraform: red y datos (pendiente)
- Fase 2 — Terraform: cómputo e IAM (pendiente)
- Fase 3 — Docker + primer despliegue manual (pendiente)
- Fase 4 — Ansible: staging (pendiente)
- Fase 5 — Producción (pendiente)
- Fase 6 — CI/CD (pendiente)
- Fase 7 — Bonus (pendiente)
- Fase 8 — Documentación final (pendiente)

---

## Fase 0 — Cuentas, accesos y doble remoto

### 0.1 · Decisión: flujo de doble remoto Git (GitHub + GitLab)

**Contexto:** el repositorio de entrega/evaluación vive en GitLab (`origin`). El enunciado exige un pipeline de CI/CD en GitHub Actions con Workload Identity Federation (WIF) de GitHub — el módulo `terraform/modules/iam/main.tf` ya está escrito contra el issuer OIDC de GitHub (`https://token.actions.githubusercontent.com`). GitLab también soporta WIF/OIDC hacia GCP, pero con un issuer y sintaxis de pipeline distintos (`.gitlab-ci.yml`), y el enunciado nombra explícitamente el archivo `.github/workflows/ci-cd.yml`.

**Solución adoptada:** un mismo repositorio local puede tener **más de un remoto**. Se mantiene:
- `origin` → GitLab (`gitlab.codecrypto.academy/.../m2-4-plataforma-e-infraestructura.git`) — aquí se hace `git push origin main` como siempre, es el repo de entrega/evaluación.
- `github` → repo nuevo en GitHub (se crea vacío, ver paso 0.2) — aquí se hace `git push github main` o `git push github v1.0.0` cuando se quiere que corra el pipeline real de GitHub Actions.

El código de `.github/workflows/ci-cd.yml` es un archivo normal del repo: se sube a **ambos** remotos en cada commit/push, pero **solo se ejecuta** cuando el push llega a GitHub (GitLab ignora la carpeta `.github/`).

**Comandos (a ejecutar cuando el repo de GitHub ya exista, ver 0.2):**

```bash
# Ver remotos actuales
git remote -v

# Añadir el remoto de GitHub (no se toca origin)
git remote add github https://github.com/<tu-usuario>/<nombre-repo>.git

# Verificar que ahora hay dos remotos
git remote -v

# Push normal de trabajo diario (sigue igual, va a GitLab)
git push origin main

# Push que dispara el pipeline de GitHub Actions (cuando se quiera ejecutar CI/CD)
git push github main
git push github v1.0.0   # o el tag que corresponda
```

**Estado:** ✅ hecho — ver ejecución real más abajo (0.1-ejecución).

---

### 0.2 · Crear repo en GitHub

**Contexto:** necesario para poder añadir el remoto `github` y para que exista un lugar donde GitHub Actions pueda ejecutar el workflow.

**Pasos ejecutados (vía interfaz web github.com/new):**
1. Repositorio creado por el usuario, vacío (sin README/gitignore/license automáticos).
2. Nombre: **`acmeoms-infraestructura`**.
3. URL: `https://github.com/ftoscanomarquez/acmeoms-infraestructura.git`

**Estado:** ✅ hecho.

---

### 0.1-ejecución · Doble remoto configurado y primer push

**Comandos ejecutados:**

```bash
# Añadir el remoto de GitHub
git remote add github https://github.com/ftoscanomarquez/acmeoms-infraestructura.git

# Verificar remotos
git remote -v
# → github  https://github.com/ftoscanomarquez/acmeoms-infraestructura.git (fetch/push)
# → origin  https://gitlab.codecrypto.academy/.../m2-4-plataforma-e-infraestructura.git (fetch/push)

# Commit de los documentos de seguimiento (PROGRESO.md + esta bitácora)
git add PROGRESO.md oms-platform/BITACORA-COMANDOS.md
git commit -m "docs: plan de trabajo por fases y bitacora de comandos"
# → commit 8326a5e

# Push al remoto de entrega/evaluación (GitLab)
git push origin main
# → 34eb58e..8326a5e  main -> main

# Push al remoto de CI/CD (GitHub) — primera vez, repo vacío
git push github main
# → * [new branch]      main -> main
```

**Resultado obtenido:** ambos remotos quedaron sincronizados con el mismo historial y el mismo commit `8326a5e` en `main`. No hubo conflictos (el repo de GitHub se creó vacío, sin inicialización automática, tal como se previó).

**Hallazgos:** ninguno — el flujo de doble remoto funcionó exactamente como se documentó en la sección 0.1. A partir de ahora, el flujo de trabajo diario es:
- `git push origin main` → siempre, es la entrega/evaluación en GitLab.
- `git push github main` o `git push github <tag>` → solo cuando se quiera que corra el pipeline de GitHub Actions (a partir de la Fase 6).

**Estado:** ✅ hecho — 2026-09-20.

---

### 0.3 · Activar créditos gratuitos de GCP

**Contexto:** el usuario ya tiene cuenta de Google pero no había activado el programa "Comenzar gratis" (Free Trial), necesario para cubrir los servicios que no tengan capa gratuita permanente (ej. Cloud Load Balancing, Cloud CDN).

**Pasos ejecutados (vía consola web):**
1. Activado "Comenzar gratis" / "Free Trial" desde [console.cloud.google.com](https://console.cloud.google.com).
2. Cuenta de facturación creada: **`Mi cuenta de facturación`**, ID `016821-14729F-C92A7B`, tipo Directa, estado **Activo**.
3. Verificado en `console.cloud.google.com/billing/<ID>/credits/all`: crédito **"Free Trial" → Disponible → 100% → $5,089.20 restante**. (Existe también una línea "Free Trial → Vencido" con el mismo valor original, correspondiente a un crédito previo ya expirado — no afecta al crédito activo actual, no requiere acción.)
4. Gasto de los últimos 30 días: $0.

**Resultado obtenido:** crédito activo y disponible, listo para cubrir los recursos de pago (Cloud Load Balancing, Cloud CDN, Cloud SQL, Memorystore, etc.) que se creen en ambos proyectos.

**Estado:** ✅ hecho — 2026-09-20. (Pendiente: anotar aquí la fecha exacta de expiración del Free Trial en cuanto se localice en la consola — normalmente 90 días desde la activación.)

---

### 0.4 · Crear los proyectos GCP (staging y producción)

**Contexto:** el enunciado exige que staging y producción sean **proyectos GCP distintos** (aislamiento total de recursos, IAM y facturación entre entornos). Es también la práctica recomendada por Google: un proyecto por ambiente da aislamiento total del "blast radius" de un error, cuotas y facturación independientes, y IAM/WIF separado por entorno (el módulo `iam` ya crea un Workload Identity Pool `github-pool-${var.env}` distinto por entorno, lo cual presupone proyectos separados).

**Decisión de nombres** (los `project_id` de GCP son únicos globalmente, no solo en la cuenta del usuario):
- Staging: **`acmeoms-staging-fatm`**
- Producción: **`acmeoms-production-fatm`**

(sufijo `fatm` = iniciales de Francisco Alberto Toscano Marquez, para reducir la probabilidad de colisión con un project_id ya tomado por otra persona en el mundo)

**Ejecutado vía consola web** (console.cloud.google.com → selector de proyecto → "New Project"), en vez de por `gcloud` CLI (no estaba instalado en el equipo local en este punto — ver 0.5):

1. Proyecto `AcmeOMS Staging` creado con project_id `acmeoms-staging-fatm`.
2. Proyecto `AcmeOMS Production` creado con project_id `acmeoms-production-fatm`.
3. Ambos vinculados a la cuenta de facturación `016821-14729F-C92A7B` (verificado en `console.cloud.google.com/billing/016821-14729F-C92A7B/manage`, tabla "Proyectos vinculados con esta cuenta de facturación" muestra ambos junto con un tercer proyecto preexistente ajeno a este trabajo, `trade-remedies-mail`).

**Comandos equivalentes por CLI** (documentados por si se quiere reproducir sin consola web / con `gcloud` ya instalado):

```bash
# Crear proyecto de staging
gcloud projects create acmeoms-staging-fatm --name="AcmeOMS Staging"

# Crear proyecto de producción
gcloud projects create acmeoms-production-fatm --name="AcmeOMS Production"

# Vincular facturación a cada proyecto (se necesita el BILLING_ACCOUNT_ID, se obtiene con:)
gcloud billing accounts list

gcloud billing projects link acmeoms-staging-fatm --billing-account=016821-14729F-C92A7B
gcloud billing projects link acmeoms-production-fatm --billing-account=016821-14729F-C92A7B
```

**Qué hace cada comando:**
- `gcloud projects create` — crea un proyecto GCP nuevo (contenedor lógico de recursos, IAM y facturación independiente).
- `gcloud billing accounts list` — lista las cuentas de facturación disponibles en la cuenta de Google (necesario para saber el ID a usar).
- `gcloud billing projects link` — asocia un proyecto a una cuenta de facturación (sin esto, no se pueden crear recursos de pago).

**Estado:** ✅ hecho — 2026-09-20. Ambos proyectos creados y vinculados a facturación, confirmado por captura de pantalla del usuario en `Facturación → Administración de cuentas`.

---

### 0.5 · Instalar/verificar herramientas locales

**Contexto:** el README de `oms-platform` (tabla de pre-requisitos) exige versiones mínimas: `gcloud` ≥470, `terraform` ≥1.7, `ansible-core` ≥2.16, `docker` ≥24, Python ≥3.10.

**Comandos de verificación (se ejecutan primero para saber qué falta instalar):**

```bash
gcloud version
terraform version
ansible --version
docker version
python3 --version
```

**Estado:** ⏳ pendiente de ejecutar.

---

### 0.6 · Habilitar APIs de GCP necesarias

**Contexto:** cada servicio de GCP que se va a usar (Compute Engine, Cloud SQL, Cloud Run, Memorystore, Secret Manager, IAM Credentials, Artifact Registry) requiere que su API esté habilitada explícitamente en el proyecto antes de poder crear recursos con Terraform.

**Comando (por cada proyecto, staging y producción):**

```bash
gcloud services enable \
  compute.googleapis.com \
  sqladmin.googleapis.com \
  run.googleapis.com \
  redis.googleapis.com \
  secretmanager.googleapis.com \
  iamcredentials.googleapis.com \
  artifactregistry.googleapis.com \
  --project=<ID-PROYECTO>
```

**Qué hace:** activa el acceso programático a esos servicios en el proyecto indicado. Sin esto, Terraform fallará con errores del tipo "API not enabled" al intentar crear el primer recurso de cada servicio.

**Estado:** ⏳ pendiente.

---

### 0.7 · Crear bucket de estado remoto de Terraform

**Contexto:** Terraform necesita guardar su "estado" (qué recursos existen y su configuración actual) en algún lugar persistente y compartible. Por defecto lo guarda en un archivo local (`terraform.tfstate`), lo cual es peligroso (se puede perder, no es compartible en equipo, puede contener datos sensibles sin cifrar). Se usa un bucket de Google Cloud Storage como backend remoto.

**Comando previsto:**

```bash
gcloud storage buckets create gs://<tu-proyecto>-tfstate \
  --location=europe-west3 --uniform-bucket-level-access

gcloud storage buckets update gs://<tu-proyecto>-tfstate --versioning
```

**Qué hace:**
- `buckets create` — crea el bucket en la región `europe-west3` (misma región que la infraestructura, por REG-GDPR-001).
- `--uniform-bucket-level-access` — fuerza que el control de acceso sea uniforme a nivel de bucket (más seguro que ACLs por objeto).
- `buckets update --versioning` — activa versionado de objetos, para poder recuperar un estado anterior si algo se corrompe.

**Estado:** ⏳ pendiente — a decidir si se usa un bucket por proyecto (staging/production) o uno compartido con prefijos distintos por entorno (`terraform/main.tf` ya prevé `prefix = "oms-platform/${var.env}"`).

---

## Notas generales de la Fase 0

- Todavía no se ha ejecutado ningún comando real contra GCP ni GitHub — esta sección se irá actualizando con fechas, salidas reales y cualquier desviación respecto a lo aquí previsto.
- Cualquier ID real de proyecto, cuenta de facturación o URL de repositorio se documentará aquí en cuanto exista (evitando credenciales o tokens, solo identificadores no sensibles).
