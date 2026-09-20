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

**Estado:** ⏳ pendiente de ejecutar — depende de que el repo en GitHub exista primero (paso 0.2).

---

### 0.2 · Crear repo en GitHub

**Contexto:** necesario para poder añadir el remoto `github` y para que exista un lugar donde GitHub Actions pueda ejecutar el workflow.

**Pasos (vía interfaz web, se documentará el resultado aquí):**
1. Entrar a github.com con la cuenta del usuario.
2. Crear un repositorio nuevo, vacío (sin README/gitignore/license automáticos, para evitar conflictos al hacer el primer push).
3. Copiar la URL HTTPS o SSH del repo.
4. Ejecutar los comandos de `git remote add github ...` de la sección 0.1.

**Estado:** ⏳ pendiente.

---

### 0.3 · Activar créditos gratuitos de GCP

**Contexto:** el usuario ya tiene cuenta de Google pero no ha activado el programa "Comenzar gratis" ($300 USD de crédito, validez 90 días), necesario para cubrir los servicios que no tengan capa gratuita permanente (ej. Cloud Load Balancing, Cloud CDN).

**Pasos (vía consola web, se documentará el resultado aquí):**
1. Entrar a [console.cloud.google.com](https://console.cloud.google.com) con la cuenta que se usará para el proyecto.
2. Activar "Comenzar gratis" / "Free Trial" desde el banner de la consola.
3. Configurar la facturación (tarjeta de crédito/débito — GCP no cobra automáticamente al agotarse el crédito, hay que activar explícitamente la facturación de pago después).
4. Confirmar la activación y anotar aquí la fecha de expiración de los 90 días.

**Estado:** ⏳ pendiente.

---

### 0.4 · Crear los proyectos GCP (staging y producción)

**Contexto:** el enunciado exige que staging y producción sean **proyectos GCP distintos** (aislamiento total de recursos, IAM y facturación entre entornos).

**Comandos previstos (a confirmar y ajustar en el momento de ejecutar):**

```bash
# Crear proyecto de staging
gcloud projects create <ID-PROYECTO-STAGING> --name="AcmeOMS Staging"

# Crear proyecto de producción
gcloud projects create <ID-PROYECTO-PRODUCTION> --name="AcmeOMS Production"

# Vincular facturación a cada proyecto (se necesita el BILLING_ACCOUNT_ID, se obtiene con:)
gcloud billing accounts list

gcloud billing projects link <ID-PROYECTO-STAGING> --billing-account=<BILLING_ACCOUNT_ID>
gcloud billing projects link <ID-PROYECTO-PRODUCTION> --billing-account=<BILLING_ACCOUNT_ID>
```

**Qué hace cada comando:**
- `gcloud projects create` — crea un proyecto GCP nuevo (contenedor lógico de recursos, IAM y facturación independiente).
- `gcloud billing accounts list` — lista las cuentas de facturación disponibles en la cuenta de Google (necesario para saber el ID a usar).
- `gcloud billing projects link` — asocia un proyecto a una cuenta de facturación (sin esto, no se pueden crear recursos de pago).

**Estado:** ⏳ pendiente — depende de tener el ID de proyecto definitivo (se decidirá una convención de nombres, ej. `acmeoms-staging-<sufijo-random>` ya que los IDs de proyecto GCP son globalmente únicos).

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
