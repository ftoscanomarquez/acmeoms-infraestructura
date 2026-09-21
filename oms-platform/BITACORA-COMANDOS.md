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
- [Fase 1 — Terraform: red y datos](#fase-1--terraform-red-y-datos)
- [Fase 2 — Terraform: cómputo e IAM](#fase-2--terraform-cómputo-e-iam)
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

### 0.9 · Habilitar APIs de GCP necesarias

**Contexto:** conviene aclarar primero una posible confusión de vocabulario. Una "API de GCP" en este contexto **no** es lo mismo que una API de negocio (ej. un `@RestController` de Spring MVC con su Service y Repository, expuesta por la propia aplicación). Cada servicio gestionado de Google Cloud (Cloud SQL, Cloud Run, Redis/Memorystore, Secret Manager, etc.) es, por debajo, una API REST que Google opera — pero esa API viene **desactivada por defecto** en cualquier proyecto nuevo, como medida de seguridad y control de costos. Es un interruptor binario (`ENABLED`/`DISABLED`) por proyecto y por servicio: antes de que Terraform pueda crear, por ejemplo, una instancia de Cloud SQL, el proyecto necesita tener habilitada explícitamente la API `sqladmin.googleapis.com`. Si no lo está, el primer intento de crear ese recurso falla con:

```
Error: googleapi: Error 403: Cloud SQL Admin API has not been used in project ... before or it is disabled
```

Analogía con desarrollo de aplicaciones: es equivalente a tener que activar una cuenta y una API Key en un proveedor externo (ej. Stripe) antes de que tu código pueda invocar `stripe.paymentIntents.create(...)` — un paso de habilitación previo, independiente de la lógica de negocio que luego se construye sobre él.

**De dónde sale esta lista concreta de APIs** (no es arbitraria — se deriva 1 a 1 de: (a) el comando ya sugerido en `oms-platform/README.md`, y (b) los recursos `google_*` que ya están escritos en los 4 módulos de Terraform):

| API | Por qué se necesita | Recursos de Terraform que la usan |
|---|---|---|
| `compute.googleapis.com` | VPC, subredes, IPs, firewall, Load Balancer | `google_compute_network`, `google_compute_subnetwork`, `google_compute_global_address`, `google_compute_backend_service`, etc. (módulos `network` y `compute`) |
| `sqladmin.googleapis.com` | Cloud SQL (PostgreSQL) | `google_sql_database_instance`, `google_sql_database`, `google_sql_user` (módulo `database`) |
| `run.googleapis.com` | Cloud Run | `google_cloud_run_v2_service` (módulo `compute`) |
| `redis.googleapis.com` | Memorystore Redis | `google_redis_instance` (módulo `database`) |
| `secretmanager.googleapis.com` | Secret Manager (password de la BD) | `google_secret_manager_secret` (módulo `database`) |
| `iamcredentials.googleapis.com` | Necesaria para que WIF pueda generar tokens de acceso temporales para el Service Account de CI/CD | soporta `google_iam_workload_identity_pool_provider` (módulo `iam`) |
| `artifactregistry.googleapis.com` | Repositorio de imágenes Docker (`image_repo` en `envs/*.tfvars` apunta a `europe-west3-docker.pkg.dev/...`); el módulo `iam` ya otorga `roles/artifactregistry.writer` al SA de CI/CD | usada en Fase 3 (build/push de la imagen) y ya asumida por el módulo `iam` |

(Nota: `cloudkms.googleapis.com` se habilitará más adelante, solo si se llega a implementar el bonus de CMEK propia en la Fase 7 — no se activa aquí para no crear ruido en proyectos que quizá no lleguen a usarla.)

**Decisión de ejecución:** un solo comando con las 7 APIs juntas (separadas por espacio, `gcloud services enable` acepta múltiples nombres en la misma invocación) — no una por una. Se ejecuta **dos veces**, una por proyecto (`--project=acmeoms-staging-fatm` y `--project=acmeoms-production-fatm`), porque cada proyecto GCP tiene sus propios interruptores, completamente independientes del otro.

**Comando ejecutado (staging):**

```bash
gcloud services enable \
  compute.googleapis.com \
  sqladmin.googleapis.com \
  run.googleapis.com \
  redis.googleapis.com \
  secretmanager.googleapis.com \
  iamcredentials.googleapis.com \
  artifactregistry.googleapis.com \
  --project=acmeoms-staging-fatm
```

**Comando ejecutado (producción):**

```bash
gcloud services enable \
  compute.googleapis.com \
  sqladmin.googleapis.com \
  run.googleapis.com \
  redis.googleapis.com \
  secretmanager.googleapis.com \
  iamcredentials.googleapis.com \
  artifactregistry.googleapis.com \
  --project=acmeoms-production-fatm
```

**Qué hace:** activa el acceso programático a esos servicios en el proyecto indicado. Sin esto, Terraform fallará con errores del tipo "API not enabled" al intentar crear el primer recurso de cada servicio.

**Resultado obtenido (staging):**

```
Operation "operations/acf.p2-668851924327-a28ffe94-29c9-43ae-ae5f-ab2c425c5d9b" finished successfully.
```

Las 7 APIs quedaron habilitadas en `acmeoms-staging-fatm` sin errores. El comando tardó más de 2 minutos (normal, es la primera activación en un proyecto nuevo).

**Resultado obtenido (producción):**

```
Operation "operations/acf.p2-982350171486-5b91bdf0-76c8-49c9-9b27-cfa9ca127af6" finished successfully.
```

Las 7 APIs quedaron habilitadas en `acmeoms-production-fatm` sin errores.

**Estado:** ✅ hecho en ambos proyectos — 2026-09-21.

---

### 0.7 · Crear bucket de estado remoto de Terraform

**Contexto — para qué sirve el "estado" de Terraform:** cuando Terraform crea infraestructura, necesita llevar un registro de qué existe y cómo está configurado — el "estado" (`terraform.tfstate`, un archivo JSON). Es la única forma en que Terraform distingue "esto ya existe, no lo toques" de "esto es nuevo, hay que crearlo", y "esto cambió en el código, hay que actualizarlo" de "esto se borró del código, hay que destruirlo".

**Por qué no se deja como archivo local (comportamiento por defecto):**
1. **Se puede perder** — si se borra la carpeta o se pierde el archivo, Terraform "olvida" que la infraestructura existe y en el siguiente `apply` intentaría crear todo de nuevo, chocando con lo que ya existe en GCP.
2. **No es compartible** — otra máquina (o los runners de GitHub Actions en la Fase 6) no tendría ese archivo y no sabría qué ya existe.
3. **Puede contener datos sensibles sin cifrar** en texto plano dentro del JSON.
4. **Sin bloqueo de concurrencia** — dos ejecuciones simultáneas con estado local podrían corromper el registro.

**Solución:** backend remoto en un bucket de Google Cloud Storage (persistente, versionado, con bloqueo de concurrencia nativo) — es justo lo que ya está preparado, comentado, en `terraform/main.tf`:

```hcl
# terraform {
#   backend "gcs" {
#     bucket = "<tu-proyecto>-tfstate"
#     prefix = "oms-platform/${var.env}"
#   }
# }
```

**Decisión: un bucket por proyecto** (no uno compartido con prefijos), coherente con la decisión ya tomada de aislamiento total entre entornos (proyecto GCP separado por ambiente). Así, el estado de producción nunca es accesible ni modificable desde el proyecto de staging, ni comparte permisos IAM entre ambos.

**Comandos ejecutados:**

```bash
# Bucket de staging
gcloud storage buckets create gs://acmeoms-staging-fatm-tfstate \
  --project=acmeoms-staging-fatm \
  --location=europe-west3 --uniform-bucket-level-access

# Bucket de producción
gcloud storage buckets create gs://acmeoms-production-fatm-tfstate \
  --project=acmeoms-production-fatm \
  --location=europe-west3 --uniform-bucket-level-access

# Versionado en ambos (permite recuperar un estado anterior si se corrompe)
gcloud storage buckets update gs://acmeoms-staging-fatm-tfstate --versioning
gcloud storage buckets update gs://acmeoms-production-fatm-tfstate --versioning
```

**Qué hace cada flag:**
- `buckets create` — crea el bucket en la región `europe-west3` (misma región que el resto de la infraestructura, por REG-GDPR-001 — el estado de Terraform también puede contener datos sensibles, así que debe respetar la misma restricción de residencia de datos).
- `--uniform-bucket-level-access` — fuerza que el control de acceso sea uniforme a nivel de bucket vía IAM (más seguro y simple de auditar que ACLs por objeto individual).
- `buckets update --versioning` — activa versionado de objetos: cada sobrescritura del `tfstate` guarda la versión anterior, permitiendo revertir si un `apply` deja el estado en mal estado.

**Resultado obtenido:**

```
Creating gs://acmeoms-staging-fatm-tfstate/...
Creating gs://acmeoms-production-fatm-tfstate/...
Updating gs://acmeoms-staging-fatm-tfstate/... (versioning)
Updating gs://acmeoms-production-fatm-tfstate/... (versioning)
```

Ambos buckets creados en `europe-west3`, con acceso uniforme y versionado activo, sin errores.

**Pendiente para la Fase 1:** descomentar y completar el bloque `backend "gcs"` en `terraform/main.tf`, y ejecutar `terraform init -backend-config="bucket=acmeoms-staging-fatm-tfstate"` (staging) o el bucket de producción según el entorno — recordar que, según el propio comentario del archivo, el backend no admite variables de Terraform, así que el nombre del bucket se parametriza con `-backend-config` en el momento del `init`, no con `var.project_id`.

**Estado:** ✅ hecho — 2026-09-21. **Fase 0 completa al 100%.**

---

## Notas generales de la Fase 0

- Todavía no se ha ejecutado ningún comando real contra GCP ni GitHub — esta sección se irá actualizando con fechas, salidas reales y cualquier desviación respecto a lo aquí previsto.
- Cualquier ID real de proyecto, cuenta de facturación o URL de repositorio se documentará aquí en cuanto exista (evitando credenciales o tokens, solo identificadores no sensibles).

---

## Fase 1 — Terraform: red y datos

### 1.1 · Módulo `network` — resolución de los 3 TODOs (subredes, Cloud NAT, firewall)

**Contexto:** `oms-platform/terraform/modules/network/main.tf` traía 3 bloques con `TODO(alumno)` sin resolver. Se completaron los tres, documentando en el propio código (comentarios "NOTA DE DISEÑO") qué se agregó y por qué, para que quede trazable sin depender de esta bitácora. Aquí se resume la sesión de trabajo y las decisiones tomadas; el detalle conceptual completo (qué es una máscara de red, cómo se calculan los rangos CIDR, qué es VLSM, qué es NAT, qué es IAP) se explicó de forma extensa en la conversación con el usuario antes de escribir cada bloque — se referencia aquí en vez de repetirlo íntegro.

**TODO 1 · Subredes multi-zona → reinterpretado como segmentación por propósito.**

Hallazgo importante: en GCP, una subred **no está atada a una zona** — abarca automáticamente todas las zonas de la `region` indicada (a diferencia de AWS, donde sí). Por eso "dos subredes en zonas distintas" no se resuelve duplicando la misma subred, sino creando subredes con **propósitos distintos** (segmentación). Se agregó una segunda subred `connector`, reservada para el VPC Access Connector que Cloud Run necesitará en la Fase 2 para hablar con Redis por IP privada.

Cálculo de rangos usado (función `cidrsubnet(base, bits_agregados, índice)`):

```hcl
# private (ya existía):
cidrsubnet(var.vpc_cidr, 4, 0)   # /16 + 4 bits = /20 → 10.20.0.0/20 (4.096 IPs)

# connector (agregado):
cidrsubnet(var.vpc_cidr, 4, 1)   # mismo tamaño /20, índice distinto → 10.20.16.0/20
```

`cidrsubnet` corta el `/16` de origen en 2^bits_agregados franjas iguales; cada índice selecciona una franja distinta y garantizadamente disjunta de las demás — por eso basta con usar un índice distinto (1 en vez de 0) para no solaparse con `private`. Se agregaron los outputs `connector_subnet_id` y `connector_subnet_cidr` para que el módulo `compute` los consuma en la Fase 2.

**TODO 2 · Cloud NAT.**

Ningún recurso del proyecto tiene IP pública (Cloud SQL, Redis, ambas subredes). Una IP privada no es enrutable desde internet, así que cualquier conexión **saliente** hacia internet (ej. una llamada a una API externa, o una VM descargando paquetes) necesita un NAT que traduzca esa IP privada a una IP pública propia del NAT. Es tráfico de un solo sentido: nunca permite conexiones entrantes no solicitadas hacia el recurso privado.

```hcl
resource "google_compute_router" "main" { ... }        # Cloud NAT en GCP siempre cuelga de un Cloud Router
resource "google_compute_router_nat" "main" {
  nat_ip_allocate_option              = "AUTO_ONLY"                       # Google asigna las IPs públicas automáticamente
  source_subnetwork_ip_ranges_to_nat  = "ALL_SUBNETWORKS_ALL_IP_RANGES"   # aplica a todas las subredes de la VPC
  log_config { enable = true, filter = "ERRORS_ONLY" }                    # agregado por el equipo: solo logs de fallos, evita ruido
}
```

**TODO 3 · Firewall (deny-all por defecto + 3 reglas explícitas).**

GCP ya deniega todo el tráfico entrante por defecto en una VPC custom (incluso entre recursos de la misma VPC) y permite todo el saliente — las reglas creadas son excepciones puntuales sobre ese "todo cerrado":

| Regla | Qué permite | Origen (`source_ranges`) | Por qué ese rango |
|---|---|---|---|
| `allow-internal` | TCP/UDP (todos los puertos) + ICMP | `var.vpc_cidr` (10.20.0.0/16) | Sin esto, recursos de la propia VPC no podrían hablarse entre sí (ej. Cloud Run → Redis) |
| `allow-iap-ssh` | TCP 22, solo a VMs con tag `iap-ssh` | `35.235.240.0/20` | Rango oficial y fijo publicado por Google para el tráfico saliente de Identity-Aware Proxy — permite SSH sin exponer la VM ni el puerto 22 a internet. Preparado para el bastion del bonus (Fase 7), hoy no afecta a ningún recurso (nada tiene ese tag todavía) |
| `allow-lb-health-checks` | TCP 8080 | `130.211.0.0/22`, `35.191.0.0/16` | Rangos oficiales del GFE (Google Front End) desde donde salen los health checks del Load Balancer (Fase 2) hacia el puerto de la app |

**Validación ejecutada** (módulo aislado, sin backend, solo para comprobar sintaxis y referencias antes de integrarlo a la configuración raíz):

```bash
cd oms-platform/terraform/modules/network
terraform init -backend=false
terraform validate
```

Resultado:
```
Terraform has been successfully initialized!
Success! The configuration is valid.
```

Se usó `-backend=false` porque en este punto solo interesa validar sintaxis/referencias del módulo por separado, no conectar a ningún backend remoto (eso se hace desde la raíz de `terraform/` en un paso posterior de esta misma fase). Los artefactos temporales de esta validación (`.terraform/`, `.terraform.lock.hcl`) se borraron después, para no dejar residuos fuera de lugar en el repo.

**Estado:** ✅ hecho — 2026-09-21. Módulo `network` completo y validado.

---

### 1.2 · Módulo `database` — resolución de los 2 TODOs (password segura + database_flags)

**Contexto:** `oms-platform/terraform/modules/database/main.tf` traía 2 TODOs, uno de ellos crítico de seguridad: la línea `password = "TODO_USA_SECRET_MANAGER_NO_TEXTO_PLANO"` — un placeholder de texto plano que, si se hubiera dejado así y llegado a un `apply`, habría escrito una contraseña insegura y predecible en la base de datos real, además de ser exactamente el tipo de hallazgo que el enunciado penaliza con −20 pts si `gitleaks` lo detecta en el repo.

**TODO 1 · Password del usuario `oms_app` — opción elegida: `random_password` + Secret Manager.**

El enunciado ofrecía dos caminos válidos: (A) generar la password con el provider `random` y guardarla en Secret Manager, con control total para rotarla manualmente; o (B) dejar que Cloud SQL gestione la password internamente (`manage_master_user_password`), sin que ni Terraform llegue a conocer el valor en ningún momento — más estricto pero menos documentado/estándar. Se eligió la opción (A) por ser el patrón más común para Terraform + Cloud SQL y dar más control operativo.

Cadena de recursos implementada:

```hcl
resource "random_password" "db_password" {
  length            = 32
  special           = true
  override_special  = "!#$%&*()-_=+[]{}<>:?"   # conjunto seguro, evita caracteres problemáticos al pasar por CLI/API
}

resource "google_secret_manager_secret" "db_password" { ... }   # ya existía: solo el CONTENEDOR del secreto

# Agregado: la VERSIÓN del secreto con el valor real generado
resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "google_sql_user" "oms" {
  name     = "oms_app"
  instance = google_sql_database_instance.main.name
  password = random_password.db_password.result   # antes: texto plano hardcodeado
}
```

Puntos clave documentados en el código: (1) `google_secret_manager_secret` solo crea el contenedor vacío — sin `google_secret_manager_secret_version` el secreto existiría pero sin ningún valor dentro; (2) la password nunca se escribe como texto literal en ningún punto — se genera en el momento del `apply` y se referencia por nombre de recurso; (3) el valor sí queda dentro del `tfstate` (inherente a cómo funciona Terraform), protegido por los permisos del bucket de estado creado en la Fase 0, pero nunca aparece en el historial de git.

**TODO 2 · `database_flags` para logging mínimo.**

Son el equivalente gestionado de editar `postgresql.conf` a mano (Cloud SQL no da acceso al sistema de archivos del servidor). Se agregaron 3 flags:

| Flag | Valor | Por qué |
|---|---|---|
| `log_min_duration_statement` | `400` | Registra cualquier consulta que tarde más de 400ms — mismo umbral que exige NFR-PERF-002 para `POST /api/orders` p95. Permite identificar qué consulta concreta causa una latencia alta |
| `log_statement` | `ddl` | Registra solo cambios de estructura (CREATE/ALTER/DROP TABLE) — auditoría de esquema sin inflar el log con tráfico normal de SELECT/INSERT |
| `log_connections` | `on` | Registra cada nueva conexión — apoya el audit trail que exige REG-GDPR-003 |

**Validación ejecutada (módulo aislado):**

```bash
cd oms-platform/terraform/modules/database
terraform init -backend=false
terraform validate
```

Resultado: `Success! The configuration is valid.` (también descargó el provider `hashicorp/random` por primera vez, confirmando que la referencia declarada en `versions.tf` funciona).

**Validación conjunta ejecutada (raíz de `terraform/`, los 4 módulos a la vez, sin backend):**

```bash
cd oms-platform/terraform
terraform init -backend=false
terraform validate
```

Resultado: **`network` y `database` no arrojaron ningún error** — las referencias cruzadas entre ambos módulos (`module.network.network_id`, `module.network.private_subnet_id` consumidos por `database`) son correctas. Sí aparecieron 2 errores esperados en el módulo `compute` (`cdn_policy` incompleto, `Missing required argument`), porque ese módulo todavía tiene sus TODOs sin resolver — se abordará en la Fase 2. Esto confirma que la validación conjunta funciona correctamente (detecta problemas reales cuando existen, no solo "pasa siempre"), y que hasta ahora `network`+`database` están libres de errores de integración entre sí.

Artefactos temporales (`.terraform/`, `.terraform.lock.hcl`) borrados tras cada validación, tanto en los módulos aislados como en la raíz.

**Estado:** ✅ hecho — 2026-09-21. Módulo `database` completo y validado, sin conflictos con `network`. Pendiente: módulos `compute` e `iam` (Fase 2).

---

### 1.3 · Configurar el backend `gcs` real en `terraform/main.tf`

**Contexto:** `terraform/main.tf` traía el bloque de backend comentado, con una advertencia explícita: *"El backend NO puede usar variables — tienes que parametrizar con `terraform init -backend-config`"*. Esto tiene una razón técnica: el bloque `backend { ... }` se procesa en el primer paso de `terraform init`, ANTES de que Terraform lea `var.env` o cualquier `.tfvars` — por eso no admite interpolación (`${var.env}` ahí sería un error de sintaxis).

**Solución implementada:**

1. Se descomentó/completó el bloque, dejándolo **vacío de valores concretos** (solo declara el tipo de backend):

```hcl
terraform {
  backend "gcs" {}
}
```

2. Se crearon dos archivos de configuración de backend, uno por entorno, para no tener que escribir el `-backend-config` completo a mano cada vez:

`oms-platform/terraform/envs/staging.backend.hcl`:
```hcl
bucket = "acmeoms-staging-fatm-tfstate"
prefix = "oms-platform/staging"
```

`oms-platform/terraform/envs/production.backend.hcl`:
```hcl
bucket = "acmeoms-production-fatm-tfstate"
prefix = "oms-platform/production"
```

(Referencian los buckets ya creados en la Fase 0 § 0.7 — ninguno contiene secretos, solo el nombre del bucket y la ruta de prefijo.)

**Comando ejecutado (staging):**

```bash
cd oms-platform/terraform
terraform init -backend-config=envs/staging.backend.hcl
```

**Resultado obtenido:**
```
Initializing the backend...
Successfully configured the backend "gcs"!
...
Terraform has been successfully initialized!
```

**Verificación independiente en GCP** (confirmar que el backend realmente escribió algo en el bucket, no solo que el comando "no dio error"):

```bash
gcloud storage ls gs://acmeoms-staging-fatm-tfstate/ --recursive
```

Resultado:
```
gs://acmeoms-staging-fatm-tfstate/oms-platform/staging/default.tfstate
```

Confirmado: el archivo de estado ya existe en la ruta exacta configurada (`prefix = "oms-platform/staging"`). Para producción, el mismo flujo con `-backend-config=envs/production.backend.hcl` apuntaría al bucket `acmeoms-production-fatm-tfstate` (no ejecutado todavía en esta sesión, se hará en la Fase 5).

**Hallazgo/corrección — `.gitignore` casi vacío:** al revisar qué archivos generaba `terraform init` localmente (carpeta `.terraform/`, con providers descargados y un `terraform.tfstate` local que es solo un PUNTERO al backend remoto, no el estado real de infraestructura), se detectó que el `.gitignore` del repo solo excluía `.DS_Store`. Se agregaron las exclusiones estándar de Terraform, Ansible y Python:

```gitignore
**/.terraform/
*.tfstate
*.tfstate.*
*.tfplan
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
*.retry
.ansible/
__pycache__/
*.pyc
```

Nota importante: **`.terraform.lock.hcl` NO se ignora** — ese archivo sí debe versionarse (fija las versiones exactas de providers para reproducibilidad; es el propio Terraform quien recomienda incluirlo en el control de versiones). Solo se ignora la carpeta `.terraform/` completa (los binarios descargados), no el archivo de lock que vive junto a ella. Los `.tfvars` de `envs/` tampoco se ignoran a propósito — no contienen secretos (solo `project_id`, tier, etc.) y deben quedar versionados según exige el enunciado.

**Estado:** ✅ hecho — 2026-09-21 (staging). Producción pendiente para la Fase 5.

---

### 1.4 · Completar `variables.tf` y `envs/*.tfvars`; primer `terraform plan` dirigido a staging

**Contexto:** para poder ejecutar un `terraform plan` real (aunque sea dirigido solo a `network`+`database`), hacían falta dos cosas más: (1) resolver el TODO de validación de región en `terraform/variables.tf`, y (2) reemplazar los placeholders `TODO-...` de `envs/staging.tfvars` y `envs/production.tfvars` con valores reales.

**TODO de `variables.tf` — validación de región insuficiente.**

La condición original `startswith(var.region, "europe-")` no bastaba: GCP tiene regiones que empiezan literalmente con `"europe-"` pero NO están dentro de la Unión Europea — `europe-west2` (Londres, Reino Unido, fuera de la UE tras el Brexit) y `europe-west6` (Zúrich, Suiza, nunca fue miembro de la UE). Aceptar cualquiera de esas dos violaría REG-GDPR-001 (residencia de datos en la UE, no solo "Europa geográfica"). Se reemplazó por una allowlist explícita de regiones GCP que sí están en la UE (mismo patrón que la validación de `env`): `europe-west1/3/4/8/9/12`, `europe-southwest1`, `europe-north1`, `europe-central2`.

**`envs/staging.tfvars` y `envs/production.tfvars` — placeholders reemplazados:**

| Variable | Antes | Ahora |
|---|---|---|
| `project_id` (staging) | `TODO-acme-oms-staging` | `acmeoms-staging-fatm` |
| `project_id` (production) | `TODO-acme-oms-production` | `acmeoms-production-fatm` |
| `github_repository` (ambos) | `TODO-org/oms-platform` | `ftoscanomarquez/acmeoms-infraestructura` |
| `image_repo` (ambos) | `.../TODO-project/oms` | `europe-west3-docker.pkg.dev/<project_id-real>/oms` |
| `image_sha` (ambos) | `sha256:TODO_...` | placeholder explícito con nota "PENDIENTE_FASE_3/5" — no se puede completar de verdad hasta construir la imagen Docker |

**Hallazgo — `-target` no evita que Terraform parsee TODA la configuración.**

Primer intento de plan dirigido:

```bash
terraform plan -var-file=envs/staging.tfvars -target=module.network -target=module.database
```

Resultado: **falló** con el mismo error de sintaxis en `compute` que ya habíamos visto en la validación conjunta (§ 1.2) — `cdn_policy` sin `cache_key_policy` ni `signed_url_cache_max_age_sec`. Esto reveló algo importante sobre cómo funciona `-target`: **limita qué recursos se van a crear/modificar, pero Terraform necesita parsear y validar la sintaxis de TODO el archivo de configuración primero**, porque `main.tf` conecta los 4 módulos entre sí en un único grafo de dependencias (`module.compute` referencia `module.database.db_connection_name`, `module.iam` referencia `module.compute.cloud_run_service_account`) — no puede "saltarse" la lectura de un módulo aunque luego no vaya a aplicarlo.

**Decisión:** en vez de adelantar toda la Fase 2, se corrigió ÚNICAMENTE el error puntual de sintaxis en `cdn_policy` (agregando el `cache_key_policy` mínimo obligatorio), dejando el resto del diseño de la política de CDN para la Fase 2 / bonus "Cloud CDN políticas finas":

```hcl
cdn_policy {
  cache_mode        = "CACHE_ALL_STATIC"
  default_ttl       = 3600
  max_ttl           = 86400
  negative_caching  = true
  serve_while_stale = 86400

  cache_key_policy {
    include_host         = true
    include_protocol     = true
    include_query_string = false   # provisional: se afinará en la Fase 2/bonus
  }
}
```

**Segundo intento del plan — exitoso:**

```bash
terraform plan -var-file=envs/staging.tfvars -target=module.network -target=module.database
```

Resultado:
```
Plan: 17 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + db_connection_name = (known after apply)
  + redis_host         = (known after apply)
```

Los 17 recursos coinciden exactamente con lo diseñado: VPC, 2 subredes (`private`, `connector`), router + Cloud NAT, 3 reglas de firewall, la conexión de peering privado para Cloud SQL, la instancia de Cloud SQL, la base de datos `oms`, el usuario `oms_app`, la password aleatoria, el secreto y su versión, y la instancia de Redis. 0 cambios inesperados, 0 destrucciones — coherente con que nada de esto existe todavía en el proyecto `acmeoms-staging-fatm`.

Apareció el warning esperado y benigno de Terraform: *"Resource targeting is in effect... The -target option is not for routine use"* — es el recordatorio estándar de que `-target` es para casos excepcionales; se usa aquí deliberadamente por la decisión ya documentada (cerrar la Fase 1 sin adelantar la Fase 2 completa).

---

### 1.5 · Preguntas de gestión antes del `apply`: destrucción y aplicación incremental

Antes de ejecutar el `apply` real, se aclararon dos dudas operativas del usuario:

**¿Cómo se destruye esto después?** Con `terraform destroy -var-file=envs/staging.tfvars` — borra exactamente los recursos que Terraform tiene registrados en su `tfstate`. Importante: `google_sql_database_instance.main` tiene `deletion_protection = true` y `lifecycle { prevent_destroy = true }` (protecciones ya presentes en el código original, exigidas por el enunciado) — un `destroy` normal **fallará a propósito** contra esa instancia como salvaguarda. Para destruir de verdad al cerrar el proyecto (Fase 8), habrá que desactivar esas protecciones explícitamente primero.

**¿Se puede aplicar "lo que falta" después sin re-crear lo ya aplicado?** Sí — es el comportamiento normal de Terraform. Cuando más adelante se complete `compute`/`iam` (Fase 2) y se ejecute un `apply` sin `-target` (todo el proyecto), Terraform compara el estado real actual (lo que ya existe: `network`+`database`, creados ahora) contra el código completo, y **solo crea lo que todavía no existe** — no vuelve a tocar ni recrea lo que ya está aplicado. Ese es el propósito central del archivo de estado remoto configurado en la Fase 0/1.3.

**Comando ejecutado (apply real contra staging):**

```bash
terraform apply -var-file=envs/staging.tfvars -target=module.network -target=module.database -auto-approve
```

**Resultado — falló parcialmente (exit code 1), con un hallazgo claro de causa raíz.**

Recursos creados EXITOSAMENTE antes del fallo: `random_password`, `google_secret_manager_secret` + su versión, la VPC completa (`oms-staging-vpc`), ambas subredes (`private`, `connector`), el router, Cloud NAT, las 3 reglas de firewall, y el rango de direcciones reservado para el peering (`private_service_range`) — 12 de los 17 recursos planeados.

**3 recursos fallaron, todos por la MISMA causa raíz:**

```
Error: googleapi: Error 403: Service Networking API has not been used in project 668851924327
before or it is disabled... service: "servicenetworking.googleapis.com"
  with module.network.google_service_networking_connection.private_vpc_connection

Error: Error, failed to create instance oms-staging-postgres: ...SERVICE_NETWORKING_NOT_ENABLED
  with module.database.google_sql_database_instance.main

Error: ...Google private service access is not enabled...
  with module.database.google_redis_instance.cache
```

**Diagnóstico:** la API **`servicenetworking.googleapis.com`** (Service Networking API) sustenta el mecanismo de Private Service Connect (`google_service_networking_connection`, el que conecta la VPC con la red interna de Google para que Cloud SQL/Redis tengan IP privada) — y **no se incluyó en la lista de 7 APIs habilitadas en la Fase 0 § 0.9**. Fue un descuido: en aquel momento se derivaron las APIs a partir de los recursos `google_*` "directos" de cada módulo, pero esta API de soporte no salta a la vista tan obviamente porque ningún recurso se llama literalmente "service networking" — solo aparece al usarla en tiempo de ejecución. Los otros dos errores (Cloud SQL y Redis) son consecuencias en cadena: ambos dependen de que `private_vpc_connection` exista primero.

**Por qué esto no fue una pérdida de trabajo:** es la prueba práctica de por qué usar backend remoto con estado (Fase 1.3) importa — los 12 recursos que sí se crearon quedan registrados en el `tfstate`; al reintentar, Terraform no los vuelve a crear, solo reintenta los 3 que fallaron.

**Corrección aplicada:**

```bash
gcloud services enable servicenetworking.googleapis.com --project=acmeoms-staging-fatm
gcloud services enable servicenetworking.googleapis.com --project=acmeoms-production-fatm
```

(Se habilitó también en producción de una vez, para no repetir el mismo error cuando se llegue a la Fase 5.)

**Reintento 1 del apply (tras habilitar Service Networking API):**

```bash
terraform apply -var-file=envs/staging.tfvars -target=module.network -target=module.database -auto-approve
```

Resultado: `Plan: 5 to add` (no 17 — confirma que Terraform reconoció los 12 recursos ya creados en el `tfstate` y solo reintentó los que faltaban). `private_vpc_connection` se creó exitosamente esta vez (tardó 1m2s). Pero **Cloud SQL y Redis volvieron a fallar**, con un error distinto y más revelador:

```
Error: Error, failed to create instance because the network doesn't have at least 1 private
services connection. Please see https://cloud.google.com/sql/docs/mysql/private-ip#network_requirements
  with module.database.google_sql_database_instance.main

Error: ...Google private service access is not enabled...
  with module.database.google_redis_instance.cache
```

**Diagnóstico — condición de carrera (race condition), no un problema de configuración ni de APIs.** El log mostraba `private_vpc_connection: Creating...`, `redis: Creating...` y `sql_database_instance: Creating...` lanzados los TRES al mismo tiempo. Aunque Cloud SQL y Redis dependen lógicamente de que el peering exista primero, en el código **no había ninguna dependencia explícita** entre esos recursos — `private_network = var.network_id` en Cloud SQL apunta a la VPC en sí, no a la conexión de peering, así que Terraform no tenía forma de saber que debía esperar. Sin `depends_on` explícito, Terraform paraleliza agresivamente todo lo que no tenga una referencia directa entre argumentos.

**Corrección aplicada — `depends_on` explícito entre módulos:**

1. Nuevo output en `modules/network/main.tf`: `private_vpc_connection_id`, exponiendo el ID de `google_service_networking_connection.private_vpc_connection`.
2. Nueva variable de entrada en `modules/database/main.tf`: `private_vpc_connection_id` (usada ÚNICAMENTE para forzar el orden, no para ninguna configuración real).
3. `depends_on = [var.private_vpc_connection_id]` agregado tanto en `google_sql_database_instance.main` como en `google_redis_instance.cache`.
4. Conectado en `terraform/main.tf`: `private_vpc_connection_id = module.network.private_vpc_connection_id` al invocar `module "database"`.

**Reintento 2 del apply — ÉXITO TOTAL:**

```bash
terraform apply -var-file=envs/staging.tfvars -target=module.network -target=module.database -auto-approve
```

`Plan: 4 to add` (ya no 5 — `private_vpc_connection` reconocido en el estado, sin cambios). Con el `depends_on` en efecto, Redis y Cloud SQL se crearon sin errores esta vez:

```
module.database.google_redis_instance.cache: Creation complete after 4m23s
  [id=projects/acmeoms-staging-fatm/locations/europe-west3/instances/oms-staging-redis]
module.database.google_sql_database_instance.main: Creation complete after 5m8s
  [id=oms-staging-postgres]
module.database.google_sql_user.oms: Creation complete after 1s
module.database.google_sql_database.oms: Creation complete after 2s

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:
db_connection_name = "acmeoms-staging-fatm:europe-west3:oms-staging-postgres"
redis_host = "10.152.126.148"
```

**Resumen del proceso completo de aplicación de la Fase 1 (los 17 recursos, en 3 tandas):**

| Intento | Resultado | Recursos creados | Causa del fallo (si hubo) |
|---|---|---|---|
| 1 | Falló | 12/17 (VPC, subredes, NAT, firewall, secret) | Faltaba habilitar `servicenetworking.googleapis.com` |
| 2 | Falló | +1/17 (`private_vpc_connection`) | Condición de carrera: Cloud SQL/Redis se lanzaron en paralelo sin `depends_on` |
| 3 | ✅ Éxito | +4/17 (Redis, Cloud SQL, database, user) | — |

**Lección clave para reproducir esto en el futuro:** en Terraform, una dependencia *lógica* entre recursos de módulos distintos (ej. "Cloud SQL necesita que el peering exista") **no se infiere automáticamente** salvo que haya una referencia directa de un atributo a otro. Si dos recursos no comparten un argumento que los conecte, hay que declarar `depends_on` explícitamente — de lo contrario Terraform los paraleliza agresivamente y pueden fallar por orden de creación, incluso si "deberían" funcionar en teoría.

**Estado:** ✅ hecho — 2026-09-21. **Los 17 recursos de `network`+`database` existen realmente en el proyecto `acmeoms-staging-fatm`.**

---

### 1.6 · Verificación cruzada: API directa de GCP + consola visual

**Contexto:** no basta con confiar en que Terraform reportó "Apply complete" — se verificó independientemente contra la API real de GCP (con comandos `gcloud ... list`, sin pasar por Terraform) y visualmente en la consola web.

**Comandos ejecutados:**

```bash
gcloud sql instances list --project=acmeoms-staging-fatm --format='table(name,databaseVersion,region,state)'
gcloud redis instances list --region=europe-west3 --project=acmeoms-staging-fatm --format='table(name,tier,state)'
gcloud compute networks list --project=acmeoms-staging-fatm --format='table(name)'
gcloud compute networks subnets list --project=acmeoms-staging-fatm --format='table(name,region,ipCidrRange)'
```

**Resultado — todo confirmado:**

| Recurso | Confirmado por API |
|---|---|
| Cloud SQL | `oms-staging-postgres`, `POSTGRES_16`, `europe-west3`, estado `RUNNABLE` |
| Redis | `oms-staging-redis`, `STANDARD_HA`, estado `READY` |
| VPC | `oms-staging-vpc` (además de `default`, la red automática de GCP no relacionada con este proyecto) |
| Subred `private` | `10.20.0.0/20`, `europe-west3` — coincide exactamente con el diseño (índice 0 de `cidrsubnet`) |
| Subred `connector` | `10.20.16.0/20`, `europe-west3` — coincide exactamente con el diseño (índice 1) |

(El listado de subredes también mostró decenas de subredes `default` en cada región del mundo — son automáticas de GCP en cualquier proyecto nuevo, no relacionadas con este trabajo, se filtran mentalmente al buscar el prefijo `oms-staging-*`.)

**URLs de verificación visual en consola** (documentadas para reutilizar en producción cambiando el project_id, y para volver a revisar en cualquier momento):

| Recurso | URL |
|---|---|
| VPC | `https://console.cloud.google.com/networking/networks/details/oms-staging-vpc?project=acmeoms-staging-fatm` |
| Subredes (listado) | `https://console.cloud.google.com/networking/networks/subnetworks?project=acmeoms-staging-fatm` |
| Cloud Router + NAT | `https://console.cloud.google.com/net-services/nat/list?project=acmeoms-staging-fatm` |
| Reglas de Firewall | `https://console.cloud.google.com/networking/firewalls/list?project=acmeoms-staging-fatm` |
| Cloud SQL | `https://console.cloud.google.com/sql/instances/oms-staging-postgres/overview?project=acmeoms-staging-fatm` |
| Memorystore Redis | `https://console.cloud.google.com/memorystore/redis/locations/europe-west3/instances/oms-staging-redis/details?project=acmeoms-staging-fatm` |
| Secret Manager | `https://console.cloud.google.com/security/secret-manager/secret/oms-staging-db-password/versions?project=acmeoms-staging-fatm` |

**Qué se espera ver en cada una:** VPC en modo subredes "personalizado"; ambas subredes en `europe-west3` con los rangos ya indicados; Cloud SQL en estado verde "Runnable" con alta disponibilidad (por `REGIONAL`); Redis en nivel "Estándar" y estado "Listo"; el secreto con exactamente 1 versión (la password generada por `random_password`).

---

## Fase 2 — Terraform: cómputo e IAM

### 2.1 · Módulo `compute` — resolución de los 3 TODOs (probes, VPC connector, SSL/HTTPS/forwarding rule)

**Contexto:** `oms-platform/terraform/modules/compute/main.tf` traía 3 TODOs. Se resolvieron los tres, con el mismo patrón de comentarios "NOTA DE DISEÑO" en el código que en fases anteriores.

**TODO 1 · startup_probe y liveness_probe contra `/healthz`.**

Cloud Run no lee el `HEALTHCHECK` nativo de Docker (ya presente en el Dockerfile) — tiene su propio mecanismo de sondas, con dos tipos de propósito distinto:

- `startup_probe`: se ejecuta SOLO al arrancar un contenedor nuevo. Mientras no pase, Cloud Run no envía tráfico real a esa instancia.
- `liveness_probe`: se ejecuta de forma continua durante toda la vida de la instancia. Si falla repetidamente, Cloud Run reinicia el contenedor automáticamente — mecanismo técnico detrás de OPS-007 ("degradar suavemente, sin intervención humana inmediata").

```hcl
startup_probe {
  http_get { path = "/healthz", port = 8080 }
  initial_delay_seconds = 5
  period_seconds         = 5
  timeout_seconds        = 3
  failure_threshold      = 6
}
liveness_probe {
  http_get { path = "/healthz", port = 8080 }
  period_seconds    = 10
  timeout_seconds   = 3
  failure_threshold = 3
}
```

**TODO 2 · VPC Access Connector (Cloud Run → Redis por IP privada).**

Cloud Run vive por defecto FUERA de la VPC (red gestionada de Google), sin visibilidad de recursos privados como Redis. El VPC Access Connector es el puente: vive dentro de una subred de la VPC — específicamente la subred `connector` (`10.20.16.0/20`) que se preparó en la Fase 1 justo para este propósito — y reenvía el tráfico de Cloud Run hacia la red privada.

```hcl
resource "google_vpc_access_connector" "redis" {
  name          = "oms-${var.env}-connector"
  region        = var.region
  subnet { name = var.connector_subnet_id }
  min_instances = 2
  max_instances = 3
}
```

Conectado en el `template` de Cloud Run con `vpc_access { connector = ..., egress = "ALL_TRAFFIC" }` — se eligió `ALL_TRAFFIC` (todo el tráfico saliente pasa por el connector) en vez de solo el tráfico a rangos privados, porque la salida general a internet ya la resuelve el Cloud NAT del módulo `network` sobre la misma VPC, así que no hay conflicto ni duplicidad.

Nueva variable de entrada `connector_subnet_id`, conectada desde `terraform/main.tf`: `connector_subnet_id = module.network.connector_subnet_id`.

**TODO 3 · Certificado SSL managed + Target HTTPS Proxy + Global Forwarding Rule.**

Cadena completa de un HTTPS Load Balancer en GCP (6 piezas): NEG → Backend Service → URL Map (las 3 primeras ya existían) → **Certificado SSL → Target HTTPS Proxy → Global Forwarding Rule** (las 3 que faltaban).

**Decisión de diseño discutida con el usuario — dominio placeholder:** un certificado SSL managed de Google requiere un dominio real con un registro DNS tipo A apuntando a la IP del Load Balancer, para que Google pueda validarlo y emitirlo. Un dominio es un recurso que se compra por separado a un registrador (Namecheap, Cloudflare, etc., ~$10-15 USD/año) — **no lo provee ni lo cubre el crédito de GCP**, es una industria completamente distinta del propio Google Cloud. Se decidió usar un placeholder explícito (`PENDIENTE-DOMINIO-REAL.example.com`) mientras no exista un dominio real:

- El certificado SÍ se crea con el `apply`, pero queda en estado `PROVISIONING` indefinidamente (nunca falla el apply, simplemente nunca llega a `ACTIVE`).
- La IP pública del Load Balancer (`lb_ip`) sí se crea y es real, verificable en la consola.
- **Cloud Run sigue siendo completamente funcional y probable mientras tanto** por su propia URL nativa (`https://oms-<env>-xxxxx.a.run.app`), que ya trae HTTPS válido de fábrica sin necesitar ningún dominio propio — es la vía normal para validar la aplicación en staging antes de tener un dominio.
- Solo queda sin poder probarse end-to-end la capa de "acceso por IP fija + HTTPS del Load Balancer" hasta que exista un dominio real.

```hcl
resource "google_compute_managed_ssl_certificate" "default" {
  name = "oms-${var.env}-cert"
  managed { domains = [var.lb_domain] }
}
resource "google_compute_target_https_proxy" "default" {
  name             = "oms-${var.env}-https-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}
resource "google_compute_global_forwarding_rule" "https" {
  name                  = "oms-${var.env}-https-fr"
  ip_address            = google_compute_global_address.lb_ip.address
  port_range            = "443"
  target                = google_compute_target_https_proxy.default.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
```

Nueva variable `lb_domain` (con `default = "PENDIENTE-DOMINIO-REAL.example.com"`), agregada también en `terraform/variables.tf` y conectada en `terraform/main.tf` para poder sobreescribirla desde un `.tfvars` el día que exista un dominio real, sin tocar el módulo.

**Validación ejecutada (módulo aislado):**

```bash
cd oms-platform/terraform/modules/compute
terraform init -backend=false
terraform validate
```

Resultado: `Success! The configuration is valid.`

**Estado:** ✅ hecho — 2026-09-21.

---

### 2.2 · Módulo `iam` — resolución del TODO de roles mínimos + aclaración de un valor no evidente

**TODO · Roles del Service Account de CI/CD.**

El pipeline (Fase 6) hace 3 cosas: construir/subir la imagen Docker, desplegar en Cloud Run vía Ansible, y leer estado de Cloud Run para el traffic-splitting/verificación (los comandos `gcloud run services describe` / `revisions list` que ya usa el role `oms_cloud_run`). Se agregó un cuarto rol a los 3 ya presentes:

```hcl
locals {
  cicd_roles = [
    "roles/run.developer",            # ya existía: desplegar/gestionar Cloud Run
    "roles/iam.serviceAccountUser",   # ya existía: usar el SA de runtime al desplegar
    "roles/artifactregistry.writer",  # ya existía: docker push
    "roles/artifactregistry.reader",  # AGREGADO: Cloud Run necesita LEER la imagen al
                                       # desplegar — más correcto declararlo explícito
                                       # que asumir que "writer" ya cubre lectura.
  ]
}
```

Ningún rol amplio (`owner`/`editor`) — ninguno de los 3 pasos del pipeline necesita crear/modificar infraestructura (eso lo hace Terraform, con la autenticación humana del desarrollador).

**Hallazgo de revisión — `allowed_audiences = ["sts.amazonaws.com"]` no es un error.** Al revisar el código ya existente, este valor llamó la atención por ser un dominio de AWS dentro de un módulo de GCP. Se confirmó (contra la documentación oficial de Google para WIF + GitHub Actions) que es correcto: es el "audience" por defecto que GitHub Actions incluye en sus tokens OIDC cuando no se especifica uno distinto (valor histórico de GitHub, su primer caso de uso documentado fue con AWS) — funciona igual para cualquier proveedor receptor, incluido GCP, siempre que ese proveedor lo declare como audiencia aceptada, que es justo lo que hace esa línea. Se agregó un comentario aclaratorio en el código para que no genere la misma duda a futuro.

**Validación ejecutada (módulo aislado):** `Success! The configuration is valid.`

**Estado:** ✅ hecho — 2026-09-21.

---

### 2.3 · Validación conjunta de los 4 módulos desde la raíz

```bash
cd oms-platform/terraform
terraform validate
```

Resultado: **`Success! The configuration is valid.`** — Los 4 módulos (`network`, `database`, `compute`, `iam`) son ahora sintáctica y referencialmente correctos entre sí. Es la primera vez en el proyecto que la validación completa pasa sin ningún error (en la Fase 1 siempre había errores pendientes en `compute`).

**Siguiente paso:** `terraform plan` completo (sin `-target`) contra staging, y de ser limpio, `terraform apply` completo.

---

### 2.4 · `terraform plan` completo (sin `-target`) contra staging

**Comando ejecutado:**

```bash
cd oms-platform/terraform
terraform plan -var-file=envs/staging.tfvars
```

**Resultado — limpio:**

```
Plan: 20 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + cicd_service_account       = (known after apply)
  + cloud_run_url              = (known after apply)
  + load_balancer_ip           = (known after apply)
  + workload_identity_provider = (known after apply)
```

**0 cambios sobre los 17 recursos de `network`+`database` ya aplicados en la Fase 1** — confirma que el estado remoto sigue siendo consistente y que completar `compute`/`iam` no provocó ningún efecto colateral sobre lo ya existente. Detalle verificado en el plan: `REDIS_HOST` en las env vars de Cloud Run ya trae la IP privada real de Redis (`10.152.126.148`, la misma que se obtuvo en la Fase 1) — confirma que las referencias entre módulos (`module.database.redis_host` → `module.compute`) funcionan correctamente.

**Desglose completo de los 37 recursos totales del proyecto** (documentado a petición del usuario, para tener claridad de qué es "viejo" y qué es "nuevo" en este punto):

**17 ya existentes desde la Fase 1** (`0 to change` en este plan — reconocidos tal cual en el estado):

| # | Módulo | Recurso | Qué es |
|---|---|---|---|
| 1 | network | `google_compute_network.main` | VPC `oms-staging-vpc` |
| 2 | network | `google_compute_subnetwork.private` | Subred `10.20.0.0/20` |
| 3 | network | `google_compute_subnetwork.connector` | Subred `10.20.16.0/20` |
| 4 | network | `google_compute_global_address.private_service_range` | Rango reservado para peering |
| 5 | network | `google_service_networking_connection.private_vpc_connection` | Conexión de peering |
| 6 | network | `google_compute_router.main` | Cloud Router |
| 7 | network | `google_compute_router_nat.main` | Cloud NAT |
| 8 | network | `google_compute_firewall.allow_internal` | Regla: tráfico interno VPC |
| 9 | network | `google_compute_firewall.allow_iap_ssh` | Regla: SSH vía IAP |
| 10 | network | `google_compute_firewall.allow_lb_health_checks` | Regla: health checks del LB |
| 11 | database | `random_password.db_password` | Password generada |
| 12 | database | `google_secret_manager_secret.db_password` | Contenedor del secreto |
| 13 | database | `google_secret_manager_secret_version.db_password` | Versión con el valor |
| 14 | database | `google_sql_database_instance.main` | Instancia Cloud SQL |
| 15 | database | `google_sql_database.oms` | Base de datos `oms` |
| 16 | database | `google_sql_user.oms` | Usuario `oms_app` |
| 17 | database | `google_redis_instance.cache` | Instancia Redis |

**20 nuevos en este plan** (`to add`, Fase 2 — módulos `compute` e `iam`):

| # | Módulo | Recurso | Qué es |
|---|---|---|---|
| 18 | compute | `google_service_account.cloud_run` | SA de runtime |
| 19 | compute | `google_vpc_access_connector.redis` | VPC Access Connector (TODO#2) |
| 20 | compute | `google_cloud_run_v2_service.oms` | El servicio Cloud Run |
| 21 | compute | `google_compute_region_network_endpoint_group.cloud_run_neg` | NEG serverless |
| 22 | compute | `google_compute_backend_service.default` | Backend Service (con CDN) |
| 23 | compute | `google_compute_url_map.default` | URL Map |
| 24 | compute | `google_compute_managed_ssl_certificate.default` | Certificado SSL (TODO#3, quedará en PROVISIONING) |
| 25 | compute | `google_compute_target_https_proxy.default` | Target HTTPS Proxy (TODO#3) |
| 26 | compute | `google_compute_global_address.lb_ip` | IP pública del LB |
| 27 | compute | `google_compute_global_forwarding_rule.https` | Forwarding Rule (TODO#3) |
| 28 | iam | `google_iam_workload_identity_pool.github` | Pool WIF |
| 29 | iam | `google_iam_workload_identity_pool_provider.github` | Provider WIF |
| 30 | iam | `google_service_account.cicd` | SA del pipeline de CI/CD |
| 31 | iam | `google_service_account_iam_binding.cicd_wif` | Binding pool ↔ SA (impersonación) |
| 32 | iam | `google_project_iam_member.cicd["roles/run.developer"]` | Rol: desplegar Cloud Run |
| 33 | iam | `google_project_iam_member.cicd["roles/iam.serviceAccountUser"]` | Rol: usar SA de runtime |
| 34 | iam | `google_project_iam_member.cicd["roles/artifactregistry.writer"]` | Rol: publicar imágenes |
| 35 | iam | `google_project_iam_member.cicd["roles/artifactregistry.reader"]` | Rol: leer imágenes |
| 36 | iam | `google_project_iam_member.runtime_sql_client` | Rol: SA runtime conecta a Cloud SQL |
| 37 | iam | `google_project_iam_member.runtime_secret_accessor` | Rol: SA runtime lee el secreto |

**Siguiente paso:** `terraform apply` completo contra staging.

---

### 2.5 · `terraform apply` completo contra staging — 1er intento falla (misma clase de hallazgo que la Fase 1)

**Comando ejecutado:**

```bash
terraform apply -var-file=envs/staging.tfvars -auto-approve
```

**Resultado — falló parcialmente, 11/20 recursos creados exitosamente:** todo el módulo `iam` completo (pool WIF, provider, SA de CI/CD, binding, los 4 roles del SA de CI/CD, los 2 roles del SA de runtime) + el SA de runtime del módulo `compute` + la IP del Load Balancer + el certificado SSL (en `PROVISIONING`, como se esperaba). El error:

```
Error: Error creating Connector: googleapi: Error 403: Serverless VPC Access API has not been
used in project acmeoms-staging-fatm before or it is disabled.
  with module.compute.google_vpc_access_connector.redis
```

**Diagnóstico:** misma clase de hallazgo que en la Fase 1 (§ 1.5) — **`vpcaccess.googleapis.com`** (Serverless VPC Access API) sustenta específicamente el recurso `google_vpc_access_connector` (resuelto en el TODO#2 de `compute`), y no estaba en la lista original de 7 APIs de la Fase 0 ni se agregó después. El fallo bloqueó en cascada al resto de recursos que dependían de él (Cloud Run, NEG, backend service, url map, target https proxy, forwarding rule — 8 recursos que ni siquiera llegaron a intentarse en esta ejecución).

**Lección consolidada (ya van 2 veces con el mismo patrón):** cada vez que un módulo de Terraform introduce un tipo de recurso nuevo, conviene revisar explícitamente en la documentación de ese recurso (`google_vpc_access_connector`, `google_service_networking_connection`, etc.) cuál API de GCP lo sustenta, en vez de confiar solo en la lista de APIs ya habilitada — algunas APIs de soporte no tienen un nombre obvio que coincida con el nombre del recurso de Terraform.

**Corrección aplicada:**

```bash
gcloud services enable vpcaccess.googleapis.com --project=acmeoms-staging-fatm
gcloud services enable vpcaccess.googleapis.com --project=acmeoms-production-fatm
```

**Reintento 1 — mismo error + hallazgo adicional del certificado:**

```bash
terraform apply -var-file=envs/staging.tfvars -auto-approve
```

**Resultado:** el error de `vpcaccess.googleapis.com` **persistió**, idéntico al primer intento, a pesar de haber habilitado la API un par de minutos antes. El propio mensaje de Google lo advierte explícitamente: *"If you enabled this API recently, wait a few minutes for the action to propagate to our systems and retry"* — la habilitación de una API no es instantánea en todos los sistemas internos de GCP; 1-2 minutos no fueron suficientes.

**Hallazgo adicional (menor, no bloqueante) detectado en el mismo plan:** el certificado SSL managed apareció marcado `must be replaced`:

```
~ domains = [ # forces replacement
    ~ "pendiente-dominio-real.example.com" -> "PENDIENTE-DOMINIO-REAL.example.com",
  ]
```

**Causa:** GCP normaliza automáticamente el campo `domains` de un certificado managed a minúsculas al crearlo (guardó `pendiente-dominio-real.example.com` en el primer `apply`), pero el código seguía enviando el placeholder con mayúsculas (`PENDIENTE-DOMINIO-REAL.example.com`). Como ese campo es inmutable, Terraform detecta la diferencia permanente entre lo pedido y lo real, y fuerza destruir+recrear el certificado — esto se repetiría en CADA `apply` futuro si no se corrige. El certificado sí se destruyó y recreó exitosamente en este intento (`Creation complete after 12s`), antes de que fallara el connector.

**Corrección aplicada:** placeholder cambiado a minúsculas desde el origen, en ambos lugares donde se declara (`modules/compute/main.tf` y `variables.tf` de la raíz):

```hcl
default = "pendiente-dominio-real.example.com"  # antes: PENDIENTE-DOMINIO-REAL.example.com
```

**Reintento 2:** se decidió dar más margen de propagación a la API antes de reintentar (3 minutos vía `ScheduleWakeup`, en vez de reintentar inmediatamente).

**Resultado — la propagación de la API sí funcionó, pero apareció un error NUEVO y distinto:**

```
Plan: 7 to add, 0 to change, 0 to destroy.   ← ya no 8 con reemplazo: el fix de minúsculas del certificado funcionó
...
Error: Error creating Connector: googleapi: Error 400: Please provide a properly formatted subnet name.
  with module.compute.google_vpc_access_connector.redis
```

El error 403 de "API disabled" ya NO apareció — confirma que el margen de espera sí era lo que faltaba para ese problema. Pero surgió uno nuevo, de formato.

**Diagnóstico:** `connector_subnet_id` (el output del módulo `network` que se estaba pasando a `subnet.name`) usa el atributo `.id` de la subred, que devuelve la RUTA COMPLETA (`projects/acmeoms-staging-fatm/regions/europe-west3/subnetworks/oms-staging-connector`). Pero el campo `subnet.name` de `google_vpc_access_connector` espera específicamente el NOMBRE CORTO (`oms-staging-connector`), no la ruta completa — es una inconsistencia real entre recursos de GCP: unos consumidores esperan `.id` (ruta completa), otros esperan `.name` (nombre corto), y no hay una regla universal, hay que revisar la documentación de cada recurso.

**Corrección aplicada:**

1. Nuevo output en `modules/network/main.tf`: `connector_subnet_name` (usa `.name` en vez de `.id`), además de mantener `connector_subnet_id` ya existente (para otros posibles usos futuros que sí necesiten la ruta completa).
2. Nueva variable en `modules/compute/main.tf`: `connector_subnet_name`, usada específicamente en `subnet { name = var.connector_subnet_name }`.
3. Conectado en `terraform/main.tf`: `connector_subnet_name = module.network.connector_subnet_name`.

**Validación tras el fix:** `terraform validate` → `Success! The configuration is valid.`

**Reintento 3 — nuevo hallazgo, esta vez sobre el TAMAÑO de la subred:**

```bash
terraform apply -var-file=envs/staging.tfvars -auto-approve
```

**Resultado:** el nombre corto ya fue aceptado (`name = "oms-staging-connector"`), y el intento avanzó considerablemente más (2m20s intentando crear el recurso) antes de fallar con un error nuevo:

```
Error: Error waiting to create Connector: Error waiting for Creating Connector: Error code 3,
message: Operation failed: Subnets used for VPC connectors must have a netmask of 28.
  with module.compute.google_vpc_access_connector.redis
```

**Diagnóstico:** este es un **requisito técnico duro y no negociable de GCP** para este tipo específico de recurso — cualquier subred usada por un VPC Access Connector debe medir EXACTAMENTE `/28` (16 IPs), ni más grande ni más chica. La subred `connector` se había diseñado en la Fase 1 con el mismo tamaño `/20` que `private` "por simplicidad" (decisión documentada en su momento, § Fase 1 1.1) — sin saber en ese momento que el connector tenía este requisito rígido. Es, retrospectivamente, el caso de uso real de VLSM (máscara de tamaño variable) que se discutió en la teoría de la Fase 1: aquí sí hacía falta un tamaño distinto y más chico que el resto de subredes.

**Corrección aplicada en `modules/network/main.tf`:** se redimensionó la subred `connector` de `/20` a `/28`, recortándola con `cidrsubnet` anidado — primero se toma el mismo `/20` reservado antes como "contenedor" (`cidrsubnet(var.vpc_cidr, 4, 1)` → `10.20.16.0/20`), y encima de ese contenedor se recorta el `/28` final (`cidrsubnet(..., 8, 0)` → `10.20.16.0/28`, sumando 8 bits: 20+8=28):

```hcl
resource "google_compute_subnetwork" "connector" {
  name = "oms-${var.env}-connector"
  ip_cidr_range = cidrsubnet(
    cidrsubnet(var.vpc_cidr, 4, 1),  # 10.20.16.0/20 (mismo "carril" reservado antes)
    8, 0                              # + 8 bits: /20 → /28 → 10.20.16.0/28
  )
  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true
}
```

**Verificación del cálculo con `terraform console`** (en vez de confiar solo en la aritmética a mano):

```bash
terraform console <<< 'cidrsubnet(cidrsubnet("10.20.0.0/16", 4, 1), 8, 0)'
# → "10.20.16.0/28"
```

Confirmado correcto. También se agregó el output `connector_subnet_name` (nombre corto) junto al ya existente `connector_subnet_id` (ruta completa), y se conectó en `modules/compute/main.tf` (nueva variable `connector_subnet_name`, usada en `subnet { name = ... }`) y en `terraform/main.tf`.

**Efecto colateral esperado:** como la subred `connector` ya existía en GCP como `/20` (creada exitosamente en la Fase 1), cambiar su `ip_cidr_range` fuerza que Terraform la destruya y recree — seguro en este punto porque ningún recurso real llegó a depender de ella todavía (el connector nunca se creó con éxito en los 3 intentos anteriores).

**Reintento 4 — hallazgo de estado inconsistente entre Terraform y GCP:**

```bash
terraform apply -var-file=envs/staging.tfvars -auto-approve
```

Plan confirmado correcto (`8 to add, 0 to change, 1 to destroy` — la subred `connector` vieja `/20` a reemplazar por la `/28`). Pero al intentar destruir la subred vieja:

```
Error: Error when reading or editing Subnetwork: googleapi: Error 400: The subnetwork resource
'.../subnetworks/oms-staging-connector' is already being used by
'projects/acmeoms-staging-fatm/zones/europe-west3-c/instances/aet-europewest3-oms--staging--connector-7zxp',
resourceInUseByAnotherResource
```

**Diagnóstico — estado inconsistente entre Terraform y la realidad de GCP:** en el Reintento 3 (el que falló por "netmask must be 28"), Terraform reportó que `google_vpc_access_connector` había fallado — pero GCP, internamente, YA había empezado a crear la infraestructura física del conector (una VM interna visible como `aet-europewest3-oms--staging--connector-7zxp`) antes de descubrir el problema de tamaño y abortar la operación. Como la operación general falló, ese conector nunca quedó registrado en el `tfstate` de Terraform — Terraform "no sabe" que existe — pero GCP sí dejó un recurso físico a medio crear, que ahora bloquea el borrado de la subred vieja que necesitamos reemplazar.

**Verificación y corrección — limpieza manual del recurso huérfano (fuera de Terraform, vía `gcloud` directo):**

```bash
# Confirmar que el conector residual existe y en qué estado
gcloud compute networks vpc-access connectors list --region=europe-west3 --project=acmeoms-staging-fatm
# → CONNECTOR_ID: oms-staging-connector, STATE: ERROR

# Eliminarlo directamente (Terraform no lo conoce, no se puede hacer vía terraform destroy)
gcloud compute networks vpc-access connectors delete oms-staging-connector \
  --region=europe-west3 --project=acmeoms-staging-fatm --quiet
```

**Lección:** cuando un `apply` de Terraform falla a media creación de un recurso, es posible que el proveedor cloud (GCP) haya dejado infraestructura física parcial que Terraform no llegó a registrar en su estado. Antes de simplemente "cambiar el código y reintentar", conviene verificar con la CLI nativa del proveedor (`gcloud list`) si quedó algo huérfano que además pueda bloquear el siguiente intento.

**Reintento 5 — la sesión de Claude Code se cortó a media ejecución, dejando el estado bloqueado:**

```bash
terraform apply -var-file=envs/staging.tfvars -auto-approve
```

**Resultado:** el plan volvió a mostrar `8 to add, 0 to change, 1 to destroy` (mismo plan que el intento anterior, correcto). La subred `connector` se destruyó y recreó exitosamente como `/28` (`Destruction complete after 34s`, `Creation complete after 35s`), y el `google_vpc_access_connector.redis` empezó a crearse — pero a los 2m20s, **la sesión de Claude Code se cortó** (proceso terminado externamente, marcado como `[killed]` en el log), dejando el `apply` sin completarse ni fallar de forma "limpia".

**Verificación tras retomar la sesión — nunca asumir el resultado de un proceso interrumpido:**

```bash
gcloud compute networks vpc-access connectors list --region=europe-west3 --project=acmeoms-staging-fatm
# → CONNECTOR_ID: oms-staging-connector, STATE: READY
```

Buena noticia: el connector **sí terminó de crearse correctamente en GCP** (estado `READY`, no `ERROR`) — la operación había avanzado lo suficiente en el proveedor cloud antes del corte. Pero como Terraform nunca recibió esa confirmación, es probable que su `tfstate` no lo supiera.

**Segundo problema encontrado al intentar diagnosticar con `terraform plan`:**

```
Error: Error acquiring the state lock
Error message: writing "gs://acmeoms-staging-fatm-tfstate/oms-platform/staging/default.tflock" failed:
googleapi: Error 412: At least one of the pre-conditions you specified did not hold., conditionNotMet
Lock Info: ID: 1789971985805513, Operation: OperationTypeApply, Who: franc@HUAWEI-MELI
```

**Diagnóstico:** el `apply` interrumpido nunca llegó a liberar el "candado" (lock) que Terraform coloca sobre el estado remoto para evitar que dos operaciones lo modifiquen a la vez (mecanismo de protección del backend `gcs` configurado en la Fase 1). Al morir el proceso de golpe (corte de sesión), ese lock quedó huérfano indefinidamente.

**Corrección aplicada — liberación manual del lock** (segura porque ya se confirmó que no hay ninguna operación real en curso, el proceso que lo generó ya no existe):

```bash
terraform force-unlock -force 1789971985805513
# → Terraform state has been successfully unlocked!
```

**Lección clave — dos aprendizajes de este incidente:**
1. **Nunca asumir el resultado de un proceso interrumpido** — hay que verificar contra la API real del proveedor (aquí, `gcloud list`) antes de decidir el siguiente paso, tal como se hizo también en el hallazgo del conector huérfano anterior.
2. **Un corte de sesión a media escritura del estado remoto puede dejar el lock bloqueado** — `terraform force-unlock` es la herramienta correcta para resolverlo, pero solo debe usarse tras confirmar que no hay una operación real en curso desde otro proceso/persona.

**Siguiente paso:** `terraform plan` (ya con el lock liberado) para confirmar el estado real y decidir si hace falta un `terraform import` del connector o si el próximo `apply` simplemente lo detecta correctamente.

**Resultado del plan tras liberar el lock:** `Plan: 7 to add, 0 to change, 0 to destroy` — ya no aparece "1 to destroy" (la subred `/28` quedó correctamente reconocida), pero `google_vpc_access_connector.redis` sigue apareciendo como `will be created`, porque Terraform no lo tiene en su estado (aunque exista físicamente en GCP con estado `READY`). Un `apply` directo en este punto fallaría con "recurso duplicado" al intentar crear algo que ya existe.

**Solución: `terraform import`** — registra un recurso real ya existente en el estado de Terraform, sin volver a crearlo.

**Primer intento — falló por olvido de `-var-file`:**

```bash
terraform import 'module.compute.google_vpc_access_connector.redis' \
  'projects/acmeoms-staging-fatm/locations/europe-west3/connectors/oms-staging-connector'
```

Al faltar `-var-file=envs/staging.tfvars`, Terraform intentó pedir cada variable de forma interactiva (`Enter a value:`) — como el comando se ejecuta sin una terminal interactiva real, el input se agotó y terminó fallando con "No value for required variable" para cada variable sin default.

**Segundo intento — exitoso:**

```bash
terraform import -var-file=envs/staging.tfvars 'module.compute.google_vpc_access_connector.redis' \
  'projects/acmeoms-staging-fatm/locations/europe-west3/connectors/oms-staging-connector'
```

Resultado:
```
Import successful!
The resources that were imported are shown above. These resources are now in
your Terraform state and will henceforth be managed by Terraform.
```

**Formato del ID de import usado:** `projects/{project}/locations/{region}/connectors/{name}` — el formato específico que exige el recurso `google_vpc_access_connector` (cada tipo de recurso de Terraform define su propio formato de ID de import; se encuentra en la documentación del provider).

**Verificación final — `terraform plan` tras el import:**

```
Plan: 6 to add, 0 to change, 0 to destroy.
```

El connector ya NO aparece en el plan (reconocido correctamente, sin diferencias), y `vpc_access.connector` en el recurso Cloud Run ya referencia su ID real (`projects/acmeoms-staging-fatm/locations/europe-west3/connectors/oms-staging-connector`) en vez de `(known after apply)`. Solo quedan los 6 recursos que genuinamente no existen todavía: `google_cloud_run_v2_service.oms`, `google_compute_backend_service.default`, `google_compute_global_forwarding_rule.https`, `google_compute_region_network_endpoint_group.cloud_run_neg`, `google_compute_target_https_proxy.default`, `google_compute_url_map.default`.

**Resumen del incidente completo del connector (Reintentos 3-5 + import):** un solo hallazgo original (tamaño de subred incorrecto) se combinó con un corte de sesión a media ejecución, generando una cadena de 3 problemas resueltos en secuencia: (1) redimensionar la subred a `/28`, (2) limpiar un connector residual en estado ERROR de un intento anterior, (3) recuperar un lock de estado huérfano tras el corte de sesión, (4) importar al estado un connector que sí se había creado correctamente en GCP pero que Terraform no llegó a registrar. Ilustra bien por qué verificar contra la API real del proveedor (nunca asumir el resultado de un proceso interrumpido) es una disciplina necesaria al trabajar con infraestructura real.

**`terraform apply` final — bloqueado por el placeholder de `image_sha`:**

```bash
terraform apply -var-file=envs/staging.tfvars -auto-approve
```

Resultado: `Plan: 6 to add` confirmado, pero falló de inmediato al crear Cloud Run:

```
Error: Error creating Service: googleapi: Error 400: Violation in CreateServiceRequest.service.template.containers[0].image:
must be a container image path in the form [hostname/]repo-path[:tag and/or @digest]
  with module.compute.google_cloud_run_v2_service.oms
```

**Diagnóstico (esperado, no un hallazgo nuevo):** el placeholder `sha256:0000...PENDIENTE_FASE_3` de `envs/staging.tfvars` no es un digest SHA-256 real (mezcla texto con ceros, no son 64 hex). A diferencia de Cloud SQL/Redis/IAM (que no validan contenido de una imagen inexistente), Cloud Run sí valida el FORMATO de la referencia de imagen al crear el servicio. Los otros 5 recursos restantes (Load Balancer completo) dependen de que Cloud Run exista, así que fallan en cascada por la misma causa.

**Decisión tomada con el usuario:** en vez de dejar la Fase 2 con esos 6 recursos pendientes hasta la Fase 3 formal, se decidió adelantar la construcción de una imagen mínima YA, para desbloquear y cerrar el 100% de la Fase 2 en esta misma sesión. Esto requiere reconocer un obstáculo real: el Dockerfile existente asume código de la aplicación OMS real (`COPY package.json`, `npm ci`, `CMD ["node", "server.js"]`), pero ese código **no existe en este repositorio y no debe existir** — el enunciado es explícito: *"Tu trabajo en este bloque NO es implementar la aplicación —eso vendrá en bloques posteriores—"*.

**Solución: un "hola mundo" placeholder de infraestructura, claramente rotulado como tal, NUNCA como la app OMS real.** Se crearon 3 archivos nuevos en `oms-platform/docker/`:

- `server.js` — servidor HTTP mínimo con el módulo nativo `http` de Node (sin Express ni dependencias de terceros), que responde `200 OK` en `/healthz` y un JSON informativo en `/`. Encabezado del archivo deja explícito que NO implementa lógica de negocio del dominio OMS.
- `package.json` — sin `dependencies`, con una `description` que documenta el propósito exacto y cita el enunciado.
- `package-lock.json` — lockfile vacío de paquetes (coherente con no tener dependencias), necesario porque el Dockerfile ya hacía `COPY package.json package-lock.json ./`.

**Hallazgo durante el primer build — `node_modules` no existe cuando no hay dependencias:**

```bash
docker build --build-arg GIT_SHA=<sha> --build-arg BUILD_DATE=<fecha> -t oms-placeholder:local .
```

Falló en la etapa de runtime:
```
Step 8/17 : COPY --from=deps /app/node_modules ./node_modules
COPY failed: stat app/node_modules: file does not exist
```

**Diagnóstico:** `npm ci --omit=dev` sobre un `package.json` SIN `dependencies` no crea la carpeta `node_modules` en absoluto (no hay nada que instalar) — y el `COPY --from=deps` de la segunda etapa multi-stage la esperaba de todos modos.

**Corrección aplicada** en `oms-platform/docker/Dockerfile`: `RUN npm ci --omit=dev && mkdir -p node_modules` — crea el directorio explícitamente si no existe, sin afectar el comportamiento cuando sí haya dependencias reales en el futuro (la app real del bloque de implementación).

**Completado también el TODO original del Dockerfile** (labels OCI): se agregó `ARG GIT_SHA` y `ARG BUILD_DATE` (inyectados en build-time, no hardcodeados) y labels adicionales (`created`, `vendor`, `title`, `description`), con `source` apuntando al repo real (`ftoscanomarquez/acmeoms-infraestructura`) en vez del placeholder `TODO-org/oms`.

**Reintento del build — exitoso:**

```bash
docker build --build-arg GIT_SHA=ff5487c2e36f5d2677ba75885730e9fa87da904f \
  --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  -t oms-placeholder:local .
```

Resultado: `Successfully built` — los 17 pasos completados, incluyendo `HEALTHCHECK`, `USER oms` (no-root), y las labels OCI con los valores reales inyectados por build-arg.

**Verificación local (antes de subir nada a GCP):**

```bash
docker run -d --name oms-test -p 18080:8080 oms-placeholder:local
curl -sS http://localhost:18080/healthz   # → {"status":"ok"}
curl -sS http://localhost:18080/          # → mensaje aclaratorio de que es un placeholder
docker logs oms-test                       # → {"event":"server_started","port":"8080"}
docker rm -f oms-test                      # limpieza del contenedor de prueba
```

Todo correcto: el placeholder responde bien a `/healthz` (el endpoint que consultarán las probes de Cloud Run y el health check del Load Balancer).

---

### 2.6 · Hallazgo de arquitectura señalado por el usuario: Artifact Registry debe gestionarse con Terraform, no a mano

**Contexto:** antes de hacer `docker push`, se necesitaba que el repositorio de Artifact Registry existiera en GCP. Se ejecutó inicialmente por comando directo:

```bash
gcloud artifacts repositories create oms --repository-format=docker \
  --location=europe-west3 --project=acmeoms-staging-fatm
```

**El usuario señaló correctamente el problema antes de continuar:** crear este recurso a mano, fuera de Terraform, es una inconsistencia real de arquitectura — Terraform nunca lo conocería, así que un futuro `terraform destroy` lo dejaría huérfano (coste indefinido, fuera de control del proyecto), y además rompe la reproducibilidad: recrear el proyecto desde cero requeriría acordarse de este paso manual aparte, contradiciendo el principio de Infraestructura como Código que exige el enunciado.

**Corrección aplicada:**

1. Se eliminó el repositorio creado a mano: `gcloud artifacts repositories delete oms --location=europe-west3 --project=acmeoms-staging-fatm --quiet` → `Deleted repository [oms]`.
2. Se agregó correctamente como recurso de Terraform en `modules/compute/main.tf`:

```hcl
resource "google_artifact_registry_repository" "oms" {
  location      = var.region
  repository_id = "oms"
  format        = "DOCKER"
  description   = "Repositorio de imágenes Docker del OMS (AcmeOMS)."
  labels        = var.labels
}
```

3. Nuevo output `artifact_registry_url` (URL completa del repo), útil para el pipeline de CI/CD en la Fase 6.

**Validación:** `terraform validate` → `Success! The configuration is valid.`

**Lección:** cualquier recurso que el proyecto necesite de forma persistente (no solo artefactos efímeros como una imagen individual) debe declararse en Terraform desde el principio, incluso si en el momento parece "más rápido" crearlo a mano para desbloquear un paso siguiente — la disciplina de Infraestructura como Código no admite atajos parciales.

**Resultado del plan:** `Plan: 7 to add` confirmado (los 6 recursos de Cloud Run/Load Balancer + el nuevo repositorio de Artifact Registry). Se decidió aplicar el repositorio PRIMERO por separado, para poder hacer el push de la imagen real cuanto antes:

```bash
terraform apply -var-file=envs/staging.tfvars \
  -target=module.compute.google_artifact_registry_repository.oms -auto-approve
```

Resultado: `Apply complete! Resources: 1 added` — repositorio creado correctamente vía Terraform esta vez (`id=projects/acmeoms-staging-fatm/locations/europe-west3/repositories/oms`).

---

## Fase 3 — Docker + primer despliegue manual

### 3.1 · Autenticar Docker con Artifact Registry: hallazgo de incompatibilidad Windows/WSL

**Contexto:** para poder subir (`docker push`) la imagen construida al repositorio de Artifact Registry recién creado, Docker necesita autenticarse contra ese registro privado.

**Primer intento — el helper estándar de gcloud:**

```bash
gcloud auth configure-docker europe-west3-docker.pkg.dev --quiet
# → Docker configuration file updated.

docker tag oms-placeholder:local europe-west3-docker.pkg.dev/acmeoms-staging-fatm/oms/oms:0.1.0
docker push europe-west3-docker.pkg.dev/acmeoms-staging-fatm/oms/oms:0.1.0
```

**Resultado:** falló al hacer push:
```
error getting credentials - err: exec: "docker-credential-gcloud": executable file not found in $PATH
```

**Diagnóstico:** el mismo tipo de problema de PATH ya visto en la Fase 0 (§ 0.5) con `gcloud`, pero esta vez sin solución tan simple. `gcloud auth configure-docker` configuró Docker para usar el helper `docker-credential-gcloud` — pero ese binario, dentro de la instalación de gcloud usada en este proyecto (el SDK de Windows, montado vía `/mnt/c/...`), es un archivo `.cmd` de Windows (`docker-credential-gcloud.cmd`), NO un ejecutable nativo de Linux. Docker, corriendo dentro de WSL, invoca el helper como un subproceso directo — no puede ejecutar un `.cmd` de Windows así, aunque esté "en el PATH" en sentido amplio (a diferencia de invocar `gcloud` como comando normal, que sí funciona por la capa de interoperabilidad de WSL con ejecutables Windows).

**Segundo intento descartado — `docker login` con token manual:** se probó autenticar con `gcloud auth print-access-token | docker login -u oauth2accesstoken --password-stdin ...`, pero falló con el MISMO error al intentar *guardar* las credenciales tras el login (el `credHelpers` configurado en `~/.docker/config.json` por el primer intento seguía apuntando al mismo `.cmd` incompatible).

**Solución aplicada — instalar un helper de credenciales nativo de Linux, sin necesitar `sudo`/`apt`:**

```bash
# Descargar el binario nativo (Go, multiplataforma) docker-credential-gcr
# — alternativa oficial de Google al helper de gcloud, distribuida como
# binario standalone en GitHub Releases, sin depender de una instalación
# completa del SDK:
curl -fsSL 'https://github.com/GoogleCloudPlatform/docker-credential-gcr/releases/download/v2.1.22/docker-credential-gcr_linux_amd64-2.1.22.tar.gz' -o /tmp/gcr.tar.gz
tar -xzf /tmp/gcr.tar.gz -C /tmp
mkdir -p ~/.local/bin
mv /tmp/docker-credential-gcr ~/.local/bin/
chmod +x ~/.local/bin/docker-credential-gcr

# Configurar Docker para usar ESTE helper (nativo) para Artifact Registry:
export PATH=$PATH:~/.local/bin
docker-credential-gcr configure-docker --registries=europe-west3-docker.pkg.dev
# → /home/franc/.docker/config.json configured to use this credential helper

# Autenticar el helper con las credenciales de gcloud ya activas:
docker-credential-gcr gcloud-auth
```

**Nota — intento previo descartado:** se intentó primero instalar el SDK completo de Google Cloud nativamente en WSL vía `apt-get install` (que habría incluido el helper nativo también), pero requería `sudo` y la sesión no soporta entrada interactiva de contraseña — se abandonó ese camino en favor del binario standalone, más simple y sin privilegios de administrador.

**Push exitoso tras la corrección:**

```bash
export PATH=$PATH:~/.local/bin
docker push europe-west3-docker.pkg.dev/acmeoms-staging-fatm/oms/oms:0.1.0
```

Resultado:
```
0.1.0: digest: sha256:99082a531fa7bbb2d284358f3af6ec0a9ac205a64272dd34a78f5d142b2a47ac size: 2051
```

**Digest real obtenido:** `sha256:99082a531fa7bbb2d284358f3af6ec0a9ac205a64272dd34a78f5d142b2a47ac`

**Lección para reproducir esto en el futuro:** cuando se trabaja con GCP CLI instalado en Windows pero se ejecutan comandos de Docker desde WSL, cualquier herramienta que dependa de invocar un binario de `gcloud` como subproceso directo (no como comando de terminal) puede fallar por la diferencia entre ejecutables `.cmd` de Windows y binarios nativos de Linux. La solución general es usar/instalar la variante nativa de Linux de esa herramienta específica, en vez de depender de la instalación de Windows para todo.

**Secuencia completa de 4 pasos, explicada al usuario durante este bloque:** `docker build` (empaqueta la app en una imagen, solo existe localmente) → autenticación (Artifact Registry es privado, protegido por IAM, Docker necesita credenciales válidas) → `docker tag` (le da a la imagen el nombre completo de destino remoto, sin duplicar contenido) → `docker push` (transfiere las capas al registro remoto; GCP calcula el digest SHA-256 real al recibirla, que es el `image_sha` que Terraform necesita).

### 3.2 · Actualizar `image_sha` con el digest real

**Cambio en `envs/staging.tfvars`:**

```hcl
# Antes:
image_repo = "europe-west3-docker.pkg.dev/acmeoms-staging-fatm/oms"
image_sha  = "sha256:0000000000000000000000000000000000000000000000000000000000PENDIENTE_FASE_3"

# Ahora:
image_repo = "europe-west3-docker.pkg.dev/acmeoms-staging-fatm/oms/oms"
image_sha  = "sha256:99082a531fa7bbb2d284358f3af6ec0a9ac205a64272dd34a78f5d142b2a47ac"
```

(Se corrigió también `image_repo`, que le faltaba el segmento del nombre de la imagen dentro del repositorio — la ruta real usada en el push fue `.../oms/oms:0.1.0`, repo `oms` + imagen `oms`.)

**Resultado del `terraform apply` final:** `Apply complete! Resources: 6 added, 0 changed, 0 destroyed.` — Cloud Run, NEG, backend service, URL map, target HTTPS proxy y forwarding rule creados exitosamente. Outputs: `cloud_run_url = "https://oms-staging-7ifhynkuua-ey.a.run.app"`, `load_balancer_ip = "136.68.140.101"`.

**Los 38 recursos totales del proyecto (network + database + compute + iam) están aplicados en GCP staging real.**

---

### 3.3 · Verificación funcional del despliegue: dos hallazgos reales antes de dar por bueno el resultado

**Contexto:** en vez de asumir que "Terraform dijo Apply complete" significa que el servicio funciona, se probó el endpoint real.

**Hallazgo 1 — política IAM vacía (403/404 en TODA ruta).**

```bash
curl -sS -w '\nHTTP_STATUS:%{http_code}\n' https://oms-staging-7ifhynkuua-ey.a.run.app/healthz
# → 404 (HTML genérico de Google)
curl .../ → 403 Forbidden (HTML genérico de Google)
```

**Diagnóstico:** `gcloud run services get-iam-policy oms-staging ...` devolvió una política vacía (sin ningún `bindings`) — Cloud Run, por defecto, NO permite invocación sin autenticación. El servicio en sí estaba sano (`status.conditions: Ready = True`, confirmado con `gcloud run services describe`), pero la capa de IAM de Google rechazaba toda petición ANTES de llegar al contenedor (de ahí el HTML de error genérico de Google, no del propio `server.js`).

**Corrección aplicada — permiso de invocación pública, vía Terraform (no manual):**

```hcl
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.oms.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
```

Justificación de `allUsers` (no un principal más restrictivo): este es un servicio HTTP público destinado a recibir tráfico de clientes finales a través del Load Balancer (arquitectura objetivo del enunciado), no un servicio interno.

`terraform apply -target=...public_invoker` → `Apply complete! Resources: 1 added`. Tras esto, `/` empezó a responder `200` con el JSON real del `server.js` — el binding funcionó.

**Hallazgo 2 — `/healthz` específicamente seguía dando 404, aunque `/` ya funcionaba.**

Diagnóstico por descarte, en este orden:
1. Se esperó margen de propagación de IAM (90s) — no cambió nada para `/healthz`, aunque `/` sí funcionaba ya con normalidad. Esto aisló el problema a la ruta específica, no a IAM.
2. Se probó forzando HTTP/1.1 en vez de HTTP/2 — mismo resultado, descartada la negociación de protocolo.
3. **La prueba definitiva:** `gcloud run services logs read oms-staging ...` — los logs del contenedor mostraban únicamente las peticiones a `/` (la de 403 antes del binding, la de 200 después), pero **ninguna de las múltiples peticiones a `/healthz`** aparecía jamás registrada.

**Diagnóstico confirmado:** `/healthz` es una ruta que **Google Front End (GFE) intercepta antes de que la petición llegue al contenedor**, en algunos productos serverless de GCP — es una convención histórica reservada internamente por Google (viene de sistemas internos de Borg/Kubernetes), no documentada de forma prominente para usuarios de Cloud Run. La petición nunca llega a Cloud Run en absoluto; GFE la resuelve por sí solo y devuelve un 404 genérico con su propio HTML de error — por eso nunca apareció en los logs del contenedor, ni con IAM correctamente configurado.

Dato curioso: las **probes internas** de Cloud Run (`startup_probe`/`liveness_probe`) SÍ habían funcionado correctamente contra `/healthz` (el servicio llegó a `Ready: True`) — sugiere que esas probes usan un mecanismo interno distinto al del tráfico público externo, que sí pasa por GFE.

**Corrección aplicada — renombrar el endpoint de `/healthz` a `/health` en TODO el proyecto:**

| Archivo | Cambio |
|---|---|
| `docker/server.js` | `if (req.url === '/healthz')` → `'/health'`, con nota explicando el hallazgo |
| `docker/Dockerfile` | `HEALTHCHECK ... http://127.0.0.1:8080/healthz` → `/health` |
| `terraform/modules/compute/main.tf` | `startup_probe`/`liveness_probe`: `path = "/healthz"` → `"/health"` (ambas, con nota explicando que estas SÍ funcionaban, pero se estandarizó por consistencia) |
| `ansible/group_vars/all.yml` | `health_path: "/healthz"` → `"/health"` (se corrigió de paso también `image_repo`, al que le faltaba el segmento del nombre de la imagen dentro del repositorio) |

**Lección para reproducir esto en el futuro:** en Cloud Run (y posiblemente otros productos serverless de GCP), evitar el nombre `/healthz` para endpoints de salud propios — usar `/health`, `/status`, `/ping` u otro nombre no convencional-reservado. El síntoma característico de este problema es: la ruta da 404/403 con HTML genérico de Google (no de tu framework/app), Y la petición nunca aparece en los logs de la aplicación, aunque otras rutas del mismo servicio sí respondan y sí queden registradas.

**Reconstrucción y nuevo push, con el fix aplicado:**

```bash
docker build --build-arg GIT_SHA=ff5487c2e36f5d2677ba75885730e9fa87da904f \
  --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) -t oms-placeholder:local .
docker tag oms-placeholder:local europe-west3-docker.pkg.dev/acmeoms-staging-fatm/oms/oms:0.1.0
export PATH=$PATH:~/.local/bin   # necesario para el credential helper en cada nueva shell
docker push europe-west3-docker.pkg.dev/acmeoms-staging-fatm/oms/oms:0.1.0
```

Nuevo digest: `sha256:fcd5c9483453625e40a4989a2edeee82a9ce6dbc78cef6c54ceabf5bcec82b25`

**`envs/staging.tfvars` actualizado con el nuevo digest.** `terraform plan` mostró correctamente `0 to add, 1 to change` — SOLO el cambio de `path` en las probes (`/healthz` → `/health`), confirmando que **`image_sha` en `staging.tfvars` NO afecta al `apply`** (el `lifecycle { ignore_changes = [template[0].containers[0].image] }` del módulo `compute` funciona exactamente como se diseñó: Terraform gestiona la "forma" del contenedor, no qué imagen corre — eso es responsabilidad exclusiva del playbook de Ansible en la Fase 4).

```bash
terraform apply -var-file=envs/staging.tfvars -auto-approve
# → Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

**Verificación final — `/health` funciona correctamente:**

```bash
curl -sSi https://oms-staging-7ifhynkuua-ey.a.run.app/health
# → HTTP/2 200, content-type: application/json
# → {"message":"Placeholder de infraestructura...", ...}
```

Nota esperada: responde el JSON de la ruta raíz `/` (no `{"status":"ok"}`) porque la imagen que sigue corriendo es la ANTIGUA (`sha256:99082a53...`, que solo conocía `/healthz`) — confirma exactamente el diseño correcto: Terraform ya no toca la imagen desplegada tras el primer `apply`, la actualización real de imagen (con el código de `/health` ya corregido) queda pendiente para el playbook de Ansible en la Fase 4.

**Estado final de la Fase 2: ✅ COMPLETA.** Los 38 recursos totales del proyecto (`network` + `database` + `compute` + `iam`) aplicados y verificados funcionalmente en `acmeoms-staging-fatm`. Cloud Run público y accesible (`https://oms-staging-7ifhynkuua-ey.a.run.app`), Load Balancer con IP fija (`136.68.140.101`, certificado en `PROVISIONING` hasta tener dominio real), WIF configurado para GitHub Actions. Pendiente para Fase 4: desplegar la imagen corregida (`sha256:fcd5c9...`) vía Ansible para que `/health` responda con el JSON correcto de la ruta de salud.
