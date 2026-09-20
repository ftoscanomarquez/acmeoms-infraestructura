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

**Resultado de la primera verificación (todas las herramientas):**

```bash
gcloud version    # → command not found (no instalado)
terraform version # → command not found (no instalado)
ansible --version # → command not found (no instalado)
docker version    # → cliente instalado (v29.2.1) pero daemon caído
python3 --version # → no instalado (solo alias de Microsoft Store)
```

**Hallazgo — PATH y terminal en Windows + VS Code:**

Al instalar un programa en Windows, el instalador agrega su carpeta al `PATH` del **sistema**, pero **los procesos de terminal ya abiertos no releen esa variable automáticamente** — solo la leen una vez, al arrancar. Como Claude Code ejecuta comandos a través de una sesión de Git Bash que ya estaba corriendo antes de instalar `gcloud`, esa sesión no lo "vería" hasta refrescar su entorno.

**Solución aplicada:** no es necesario cerrar/reiniciar VS Code ni la sesión de Claude Code (el contexto de la conversación vive en el proceso de Claude Code, no en el proceso de Bash). Basta con refrescar el `PATH` dentro de la sesión de Bash existente, o abrir una sub-terminal nueva que sí lea el `PATH` actualizado de Windows. Si el refresco simple no detecta el binario, la alternativa es invocar `gcloud` con su ruta completa de instalación (normalmente `C:\Users\<usuario>\AppData\Local\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd`) hasta que se confirme el PATH correcto.

**Instalación realizada:** instalador oficial `.exe` descargado desde `cloud.google.com/sdk/docs/install`, ejecutado por el usuario. El propio instalador abrió una terminal CMD nueva confirmando "Welcome to the Google Cloud CLI!" (esa terminal, al ser un proceso nuevo, sí detecta el PATH actualizado de Windows).

**Verificación en la sesión de Bash de Claude Code (la que ya estaba abierta antes de instalar):**

```bash
gcloud version
# → /usr/bin/bash: line 1: gcloud: command not found   (esperado, confirma el problema de PATH explicado arriba)
```

**Solución aplicada (sin cerrar VS Code ni la sesión):**

```bash
# 1. Localizar el binario instalado
ls "/c/Users/franc/AppData/Local/Google/Cloud SDK/google-cloud-sdk/bin/"
# → confirma que gcloud, gcloud.cmd, gsutil, bq, etc. sí existen ahí

# 2. Añadir esa carpeta al PATH de la sesión actual (efecto inmediato, solo dura esta sesión de Bash)
export PATH="$PATH:/c/Users/franc/AppData/Local/Google/Cloud SDK/google-cloud-sdk/bin"
gcloud version
# → Google Cloud SDK 585.0.0 (cumple de sobra el mínimo ≥470 del README)

# 3. Persistir el PATH para futuras sesiones de Bash (aunque se reinicie la terminal, no VS Code)
echo 'export PATH="$PATH:/c/Users/franc/AppData/Local/Google/Cloud SDK/google-cloud-sdk/bin"' >> ~/.bashrc
```

**Resultado obtenido:** `gcloud` detectado y funcional en la sesión de Claude Code sin reiniciar VS Code ni perder el contexto de la conversación. Persistido en `~/.bashrc` para que futuras terminales de Git Bash también lo detecten automáticamente.

**Estado (gcloud):** ✅ hecho — 2026-09-20.

---

### 0.5b · Incidente: Docker Desktop no arrancaba (integración WSL rota)

**Contexto:** al verificar `docker version`, el cliente Docker (v29.2.1) respondía pero fallaba la conexión al daemon: `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine`. Al abrir la aplicación Docker Desktop manualmente, mostró el error:

```
WSL integration with distro 'Ubuntu' unexpectedly stopped. Do you want to restart it?

running wsl distro proxy in Ubuntu distro: running proxy: running wslexec: ...
getting settings from backend: Get "http://ipc/app/settings/flat": dial unix /mnt/wsl/docker-desktop/shared-sockets/host-services/backend.sock: connect: no such file or directory
```

**Causa probable:** una actualización de Windows ocurrida justo antes dejó la integración de Docker Desktop con la distro WSL2 `Ubuntu` en un estado inconsistente (el proxy interno de Docker dentro de esa distro no lograba reconectar con el backend del host).

**Intentos de solución, en orden:**

1. **Botón "Restart it" del propio diálogo de Docker Desktop** → ❌ no resolvió el problema, el error persistió.
2. **Reinicio manual del subsistema WSL completo** (no afecta a Windows en general, ni a VS Code, ni a la sesión de Claude Code — solo a las distros Linux virtualizadas y lo que dependa de ellas):

   ```bash
   # Desde Git Bash, invocando las herramientas nativas de Windows:
   powershell.exe -Command "wsl --shutdown"
   powershell.exe -Command "wsl --status"   # confirma: Ubuntu / WSL versión 2
   ```

3. Reabrir Docker Desktop manualmente desde el menú de Windows → ✅ arrancó correctamente esta vez.

**Verificación final:**

```bash
docker version
# → Client v29.8.0, Server (Docker Desktop 4.91.0) v29.8.0 — ambos respondiendo correctamente
```

(Nota: la versión subió de 29.2.1 a 29.8.0 respecto a la primera verificación — la actualización de Windows aparentemente disparó también una actualización de Docker Desktop al reiniciarse.)

**Lección para reproducir esto en el futuro:** si Docker Desktop falla con un error de "WSL integration ... unexpectedly stopped" tras una actualización de Windows, el botón de reinicio del propio diálogo no siempre basta — `wsl --shutdown` seguido de reabrir Docker Desktop es la solución confiable.

**Estado (Docker):** ✅ hecho — 2026-09-20.

---

### 0.5c · Descubrimiento: Terraform, Ansible y Python ya estaban instalados en WSL2/Ubuntu

**Contexto:** se decidió (ver sección de decisiones en `PROGRESO.md`) instalar y ejecutar Terraform y Ansible dentro de WSL2/Ubuntu en vez de nativo en Windows, porque Ansible es más estable en Linux (su propia documentación lo recomienda) y Docker Desktop ya usa esa misma distro `Ubuntu` como backend.

**Verificación ejecutada:**

```bash
# Listar distros WSL y confirmar que Ubuntu está corriendo
powershell.exe -Command "wsl -l -v"
# → Ubuntu (Running, versión 2) es la distro por defecto

# Ejecutar comandos dentro de la distro Ubuntu desde Git Bash de Windows,
# sin necesidad de abrir una terminal WSL aparte:
wsl.exe -d Ubuntu -e bash -c "whoami && python3 --version && which terraform && which ansible"
```

**Resultado — sorpresa positiva: ya estaban instalados** (probablemente de trabajo previo del usuario en otros proyectos, ej. `cc-s02-infra-traefik` visible en las rutas montadas de Docker):

| Herramienta | Versión en WSL/Ubuntu | Mínimo exigido (README `oms-platform`) | Cumple |
|---|---|---|---|
| `gcloud` | 585.0.0 | ≥ 470 | ✅ |
| `terraform` | 1.15.8 | ≥ 1.7 | ✅ (hay 1.16.3 disponible, no obligatorio actualizar; `required_version = ">= 1.7.0"` en `versions.tf` lo acepta) |
| `ansible-core` | 2.20.1 | ≥ 2.16 | ✅ |
| `docker` (cliente WSL) | 29.1.3 | ≥ 24 | ✅ |
| `docker` (servidor/Desktop) | 29.8.0 | ≥ 24 | ✅ |
| Python | 3.14.4 | ≥ 3.10 | ✅ |

**Comando usado para verificar versiones completas:**

```bash
wsl.exe -d Ubuntu -e bash -c "terraform version; echo; ansible --version; echo; docker version; echo; gcloud version"
```

**Decisión operativa a partir de ahora:** todos los comandos de `terraform` y `ansible` de este proyecto (Fases 1 en adelante) se ejecutan **dentro de WSL2/Ubuntu**, invocados desde la terminal de Claude Code (Git Bash) con el patrón:

```bash
wsl.exe -d Ubuntu -e bash -c "cd /ruta/al/proyecto && <comando>"
```

o entrando directamente a una sesión interactiva de esa distro cuando convenga. El repositorio de trabajo (`D:\CodeCrypto\cc-s12-infraestructura`) es accesible desde WSL vía `/mnt/d/CodeCrypto/cc-s12-infraestructura`.

`gcloud` y Docker CLI están disponibles **tanto en Windows/Git Bash como en WSL/Ubuntu** (cada sistema tiene su propia instalación o acceso al mismo daemon); no hay conflicto entre usarlos desde uno u otro lado.

**Estado:** ✅ hecho — 2026-09-20. No fue necesario instalar nada adicional para Terraform/Ansible/Python.

---

### 0.6 · Autenticación de gcloud (login personal + Application Default Credentials)

**Contexto:** antes de que Terraform o Ansible puedan hablar con la API de GCP, es necesario autenticar la máquina. Son **dos autenticaciones distintas y complementarias**, no alternativas:

| | `gcloud auth login` | `gcloud auth application-default login` (ADC) |
|---|---|---|
| ¿Quién se autentica? | El usuario, para ejecutar comandos `gcloud ...` manualmente | Cualquier librería/herramienta (Terraform, SDKs) que busque credenciales automáticamente |
| Se guarda en | Configuración interna de `gcloud` | `~/.config/gcloud/application_default_credentials.json` |
| Lo usa | Tú, desde la terminal | El `provider "google"` de `terraform/main.tf` |

Esto **no es lo mismo que WIF** (Workload Identity Federation, que autentica al pipeline de GitHub Actions sin intervención humana). Es la autenticación humana previa necesaria para poder ejecutar `terraform apply` manualmente y, con ello, construir la infraestructura de WIF (módulo `iam`) que más adelante usará el pipeline por sí solo, sin login humano.

**Decisión:** ambos logins se ejecutan dentro de WSL2/Ubuntu (consistente con la decisión de correr Terraform/Ansible ahí), en una terminal Ubuntu abierta directamente por el usuario (no vía `wsl.exe -e` desde Claude Code, porque el intercambio OAuth requiere una sesión interactiva real que la herramienta de ejecución de comandos de Claude Code no soporta — intentarlo produce `ERROR: gcloud crashed (EOFError): EOF when reading a line`).

**Comando 1 — login personal:**

```bash
gcloud auth login
```

Resultado: completado sin incidentes tras seleccionar la cuenta `francisco.alberto.tm@gmail.com` y aceptar los permisos en el navegador.

**Comando 2 — Application Default Credentials (ADC), con incidentes:**

```bash
gcloud auth application-default login --no-launch-browser
```

**Incidente A:** al ejecutarlo con `--no-browser`, tras pegar la URL completa de respuesta (`https://localhost:8085/?state=...&code=...`) en el prompt "Enter the output of the above command", gcloud abortó con:

```
ERROR: gcloud crashed (Warning): Scope has changed from "https://www.googleapis.com/auth/sqlservice.login openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/cloud-platform" to "openid https://www.googleapis.com/auth/userinfo.email".
```

Es decir, el consentimiento otorgado en el navegador no incluyó todos los scopes pedidos (probablemente por no marcar todas las casillas de permisos, o por cierre prematuro del flujo).

**Incidente B:** en el segundo intento, gcloud generó un comando con `--remote-bootstrap="https://accounts.google.com/o/oauth2/auth?...&token_usage=remote"` (pensado para autenticar desde una máquina *sin* navegador, copiando ese comando completo a otra máquina que sí lo tenga). Al pegar solo el **fragmento de URL interna** directamente en el navegador (en lugar de tratarlo como parte de un comando gcloud a ejecutar), Google devolvió:

```
Error 400: invalid_request — Missing required parameter: redirect_uri
```

porque esa URL, aislada de su contexto de comando, no llevaba el `redirect_uri` que sí incluye el flujo normal.

**Solución aplicada:** abandonar el modo `--no-browser`/`--remote-bootstrap` y usar el comando simple, dejando que WSL2 reenvíe automáticamente `localhost:8085` desde el navegador de Windows hacia el proceso dentro de la distro (WSL2 moderno soporta este reenvío de forma nativa):

```bash
gcloud auth application-default login
```

Resultado: `Your browser has been opened to visit: https://accounts.google.com/...` → login y consentimiento completos en el navegador de Windows → la terminal de Ubuntu recibió la respuesta correctamente vía `localhost:8085`:

```
Credentials saved to file: [/home/franc/.config/gcloud/application_default_credentials.json]
These credentials will be used by any library that requests Application Default Credentials (ADC).
WARNING:
Cannot find a quota project to add to ADC. You might receive a "quota exceeded" or "API not enabled" error. Run $ gcloud auth application-default set-quota-project to add a quota project.
```

**Comando 3 — asignar quota project** (necesario: sin esto, las librerías que usan ADC no saben a qué proyecto de GCP facturar/contar las llamadas a la API, y podrían fallar con "quota exceeded" o "API not enabled"):

```bash
gcloud auth application-default set-quota-project acmeoms-staging-fatm
```

Resultado:
```
Credentials saved to file: [/home/franc/.config/gcloud/application_default_credentials.json]
Quota project "acmeoms-staging-fatm" was added to ADC which can be used by Google client libraries for billing and quota. Note that some services may still bill the project owning the resource.
```

**Verificación final ejecutada:**

```bash
gcloud auth list
# → ACTIVE: * / ACCOUNT: francisco.alberto.tm@gmail.com

gcloud config list
# → [core] account = francisco.alberto.tm@gmail.com / configuración activa: [default]

test -f /home/franc/.config/gcloud/application_default_credentials.json
# → el archivo existe
```

**Lección para reproducir esto en el futuro:** en WSL2, usar siempre el flujo normal de `gcloud auth login` / `gcloud auth application-default login` (sin `--no-browser` ni `--remote-bootstrap`) mientras el reenvío de `localhost` a Windows funcione — es más simple y menos propenso a errores que el modo manual de copiar/pegar URLs y códigos. El modo `--no-browser` solo es necesario en entornos verdaderamente sin navegador disponible (ej. un servidor remoto sin interfaz gráfica).

**Estado:** ✅ hecho — 2026-09-20. Login personal y ADC configurados correctamente, con quota project `acmeoms-staging-fatm`.

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
