# OMS Platform — Trabajo final Bloque 4 · Plataforma e infraestructura

Infraestructura real en Google Cloud Platform para **AcmeOMS**, un SaaS de gestión de pedidos. El enunciado completo está en [`Trabajo - enunciado.md`](../Trabajo%20-%20enunciado.md).

> **Alcance explícito**: este trabajo NO implementa la aplicación OMS. Provisiona y opera la infraestructura que la aloja — Terraform, Ansible y CI/CD — con un placeholder HTTP mínimo (`docker/server.js`) que solo existe para tener algo real que desplegar, firmar y monitorizar.

Documentación completa del proyecto:

| Documento | Contenido |
|---|---|
| Este README | Cómo arrancar, decisiones de diseño, verificación |
| [`INFRA.md`](INFRA.md) | Arquitectura real desplegada, módulos de Terraform, recursos GCP |
| [`DEPLOYMENT.md`](DEPLOYMENT.md) | Cómo desplegar con Ansible, CI/CD, canary y rollback paso a paso |
| [`OBSERVABILIDAD.md`](OBSERVABILIDAD.md) | Qué se loguea, qué se audita, cómo se detecta un problema |
| [`CERTIFICADOS.md`](CERTIFICADOS.md) | TLS, gestión de certificados, WIF/OIDC y firma de imágenes |
| [`DIAGRAMAS.md`](DIAGRAMAS.md) | Diagramas Mermaid de infraestructura y flujo de despliegue |
| [`RETROSPECTIVA.md`](RETROSPECTIVA.md) | Qué se haría distinto, deuda técnica conocida |
| [`BITACORA-COMANDOS.md`](BITACORA-COMANDOS.md) | Registro completo y reproducible de cada comando, hallazgo y fix real |
| [`../PROGRESO.md`](../PROGRESO.md) | Bitácora de alto nivel del avance por fases |

## Pre-requisitos

| Herramienta | Versión usada en este proyecto | Notas |
|---|---|---|
| `gcloud` | 585.0.0 | `gcloud auth login` + `gcloud auth application-default login` |
| `terraform` | 1.15.8 | Ejecutado desde WSL/Ubuntu — ver nota abajo |
| `ansible-core` | 2.20.1 | + `ansible-galaxy collection install -r ansible/requirements.yml` |
| `docker` | 29.8.0 | Con `docker-credential-gcr` (ver nota) |
| Python | 3.14.4 | Requerido por el plugin de inventario GCP de Ansible |

**Nota real de entorno**: este proyecto se desarrolló en Windows con WSL2 (Ubuntu). `terraform`, `ansible-core` y `gcloud` (para las operaciones que requieren su SDK completo) corren desde WSL, no desde Git Bash/MINGW64 — `terraform` en particular no está en el `PATH` de esa segunda terminal. Además, Docker en WSL necesita `docker-credential-gcr` (no `docker-credential-gcloud`, que es un `.cmd` de Windows incompatible con WSL) — instalado sin `sudo`, ver `BITACORA-COMANDOS.md` § 3.1.

## Estructura real

```
oms-platform/
├── README.md, INFRA.md, DEPLOYMENT.md, OBSERVABILIDAD.md,
│   CERTIFICADOS.md, DIAGRAMAS.md, RETROSPECTIVA.md, BITACORA-COMANDOS.md
├── docker/
│   ├── Dockerfile              ← multi-stage, no-root, HEALTHCHECK, labels OCI
│   └── server.js                ← placeholder de infraestructura (NO es el OMS real)
├── terraform/
│   ├── versions.tf, variables.tf, main.tf, outputs.tf
│   ├── envs/{staging,production}.tfvars + .backend.hcl
│   └── modules/{network,database,compute,iam}/main.tf
├── ansible/
│   ├── ansible.cfg, requirements.yml, inventory/gcp.yml
│   ├── group_vars/{all,staging,production}.yml
│   ├── playbooks/{deploy,rollback,promote-canary}.yml
│   └── roles/oms_cloud_run/tasks/main.yml
└── (raíz del repo) .github/workflows/{ci-cd,canary-decision}.yml
```

La ubicación de `.github/workflows/` en la raíz del repo (no dentro de `oms-platform/`) es un requisito técnico de GitHub Actions, no una desviación del árbol del enunciado — ver la nota al inicio de `ci-cd.yml` y `DEPLOYMENT.md`.

## Cómo arrancar

1. **Proyectos GCP reales usados en este trabajo**: `acmeoms-staging-fatm` y `acmeoms-production-fatm` (dos proyectos GCP distintos, europe-west3). APIs habilitadas: `compute`, `sqladmin`, `run`, `redis`, `secretmanager`, `iamcredentials`, `artifactregistry`, `vpcaccess`, `servicenetworking`.

2. **Buckets de estado remoto de Terraform** (uno por proyecto, ya creados):
   ```bash
   gcloud storage buckets create gs://acmeoms-staging-fatm-tfstate --location=europe-west3 --uniform-bucket-level-access
   gcloud storage buckets update gs://acmeoms-staging-fatm-tfstate --versioning
   # ídem con acmeoms-production-fatm-tfstate
   ```

3. **Init + plan + apply** (staging primero):
   ```bash
   cd terraform
   terraform init -backend-config=envs/staging.backend.hcl
   terraform plan  -var-file=envs/staging.tfvars
   terraform apply -var-file=envs/staging.tfvars
   ```
   Y luego producción, con su propio backend:
   ```bash
   terraform init -reconfigure -backend-config=envs/production.backend.hcl
   terraform apply -var-file=envs/production.tfvars
   ```

4. **WIF ya configurado** en `terraform/modules/iam/main.tf` — el `attribute_condition` real exige repositorio exacto y (tags `v*` **o** `workflow_dispatch` sobre `main`, ver `CERTIFICADOS.md`).

5. **Despliegue con Ansible** (después de tener una imagen construida y subida a Artifact Registry — ver `DEPLOYMENT.md` para el flujo completo, incluyendo el canary y el rollback):
   ```bash
   cd ansible
   ansible-galaxy collection install -r requirements.yml
   ansible-playbook playbooks/deploy.yml -e env=staging -e image_sha=sha256:<TU-SHA>
   ```

6. **CI/CD real**: push de un tag `v*` al remoto de GitHub dispara `.github/workflows/ci-cd.yml` de punta a punta. Ver `DEPLOYMENT.md` para el detalle de cada job.

## Decisiones

Tres trade-offs principales tomados durante el trabajo, más los cambios concretos hechos sobre el borrador inicial generado con IA (política de uso de IA del enunciado, sección 8).

### 1 · Cloud Run en vez de GKE Autopilot

El enunciado deja la puerta abierta a GKE Autopilot como alternativa. Se eligió Cloud Run por tres razones concretas para este proyecto: (a) el "contenedor del monolito" es *stateless* por diseño (arquitectura objetivo, sección 2 del enunciado) — no hay ninguna necesidad real de orquestación de pods, sidecars o *StatefulSets* que justifique el coste operativo de un clúster; (b) el modelo de facturación por petición de Cloud Run (`min_instances=0` en staging) es estrictamente más barato que un clúster Autopilot con un nodo mínimo siempre encendido, relevante con un crédito de $300/90 días que hay que administrar; (c) Cloud Run resuelve *nativamente* el canary y el traffic-splitting por revisión (`gcloud run services update-traffic --to-revisions=...`) — con GKE, ese mismo mecanismo habría requerido un Ingress adicional (Istio/Gateway API) que el enunciado no pide y que habría añadido superficie de configuración sin beneficio real para este alcance.

### 2 · Terraform como única fuente de verdad de la "forma" del contenedor (cpu/memoria/instancias), no Ansible

Diseño inicial (y borrador de IA): `cloud_run_cpu`, `cloud_run_memory`, `cloud_run_min_instances` y `cloud_run_max_instances` vivían declarados por duplicado — una vez en `terraform/envs/<env>.tfvars` y otra vez a mano en `ansible/group_vars/<env>.yml`. Nada los mantenía sincronizados. Esto no era solo un riesgo teórico: se detectó *drift* real durante la Fase 5 (`memory` quedó desalineada entre ambos archivos sin que nadie lo notara durante varias fases), y en producción llegó a manifestarse como un error real de cuota (`CpuAllocPerProjectRegion` excedida) porque Ansible intentaba "corregir" una CPU que Terraform ya había fijado en un valor distinto — la revisión vieja y la nueva coexistiendo superaban el límite de la región.

Corrección aplicada: los 4 valores se declaran **una sola vez**, en `terraform/envs/<env>.tfvars`, y se exponen como outputs (`terraform/outputs.tf`). El pre-task de `ansible/playbooks/deploy.yml` corre `terraform init -reconfigure -backend-config=envs/{{ env }}.backend.hcl` + `terraform output -json` y **lee** esos 4 valores en cada ejecución — nunca los declara ni los modifica por su cuenta. `group_vars/<env>.yml` documenta explícitamente por qué esos campos ya no aparecen ahí. Este es el cambio de diseño más grande respecto al primer borrador: pasar de "dos copias que alguien debe recordar sincronizar" a "una fuente de verdad, una lectura".

### 3 · Doble control humano en el canary de producción: `deploy-production` deja el canary en 10% y se detiene; una decisión explícita separada lo promueve o lo revierte

El pipeline de CI/CD, tal como se generó en el primer borrador, desplegaba el canary al 10% en producción y ahí terminaba — sin ningún mecanismo, automático o manual, para decidir después "esto se ve bien, promuévelo" o "esto está mal, revierte". Se detectó como un hueco real de diseño (señalado explícitamente durante el trabajo) y se corrigió con un **segundo workflow separado** (`canary-decision.yml`, `workflow_dispatch` únicamente, nunca disparado por push/tag) que ofrece dos decisiones humanas: `promote` con un `target_percent` validado en el rango estricto 11–100 (11 porque un valor igual o menor al que ya deja el pipeline equivaldría a no hacer nada; 100 porque en ese punto el canary pasa a ser la revisión oficial única), o `rollback` (retira el canary por completo, revirtiendo el 100% del tráfico a la revisión anterior). Ambos caminos mantienen el gate `environment: production` (aprobación manual en GitHub) — decisión consciente de mantener doble control aunque la elección del `workflow_dispatch` ya sea, en sí misma, una decisión humana explícita.

### Cambios concretos sobre el borrador de IA (3 ejemplos, política de uso de IA — sección 8 del enunciado)

1. **Se corrigió una validación de región incompleta.** El primer borrador de la validación de `region` en `terraform/variables.tf` usaba `startswith(var.region, "europe-")`, asumiendo que cualquier región cuyo nombre empezara por "europe-" cumplía REG-GDPR-001 (residencia de datos en la UE). Es falso: `europe-west2` (Londres) quedó fuera de la UE tras el Brexit, y `europe-west6` (Zúrich) nunca fue miembro de la UE — ambas regiones GCP reales que ese patrón habría aceptado incorrectamente. Se reemplazó por una *allowlist* explícita de las regiones GCP que sí están dentro de la UE.

2. **Se rechazó el uso de módulos `google.cloud.gcp_cloudrun_*` que la rúbrica pedía, tras verificar que no existen.** El borrador inicial asumía (como pide literalmente la rúbrica) que la colección `google.cloud` de Ansible tendría módulos dedicados para Cloud Run. Verificado exhaustivamente (`ansible-doc -l`, `ansible-galaxy collection list`, inspección directa de los `.py` de la colección v1.10.2 instalada): esa colección solo contiene módulos para `runtimeconfig` (un servicio GCP distinto), ningún módulo de Cloud Run existe en absoluto — laguna real y documentada del ecosistema, no una versión desactualizada del proyecto. Se optó conscientemente por `ansible.builtin.command`/`shell` contra `gcloud run`, con idempotencia propia diseñada y verificada a mano (comparación de 4 campos: imagen, cpu, memoria, max_instances), documentando la ausencia por escrito en el propio código (`ansible/roles/oms_cloud_run/tasks/main.yml`).

3. **Se corrigió un `allowed_audiences` del proveedor WIF que un borrador inicial daba por correcto sin verificar contra la acción real.** Una nota inicial (posiblemente heredada de un ejemplo de AWS/STS) fijaba `allowed_audiences = ["sts.amazonaws.com"]` en el proveedor de Workload Identity Federation, asumiendo que era el *audience* estándar para cualquier proveedor OIDC. En la práctica, `google-github-actions/auth@v2` genera el token OIDC con *audience* = la URL completa del propio proveedor WIF, no ese valor — con `allowed_audiences` fijado así, la autenticación real fallaba con `invalid_grant: The audience in ID Token [...] does not match the expected audience`. Se eliminó el campo por completo, dejando que GCP use su propio valor por defecto (la URL del proveedor), que es exactamente lo que la acción oficial ya genera.

## Verificación final

Los 7 comandos de verificación del enunciado (sección 4), tal como se ejecutaron realmente contra GCP:

```bash
# 1. Plan limpio
cd terraform
terraform init -backend-config=envs/staging.backend.hcl
terraform plan -var-file=envs/staging.tfvars

# 2. Apply real (crea toda la infra de staging)
terraform apply -var-file=envs/staging.tfvars

# 3. Idempotencia de Terraform — segunda vez, "No changes"
terraform plan -var-file=envs/staging.tfvars

# 4. Despliegue vía Ansible
cd ../ansible
ansible-playbook playbooks/deploy.yml -e env=staging -e image_sha=sha256:...

# 5. Idempotencia de Ansible — segunda vez, changed=0
ansible-playbook playbooks/deploy.yml -e env=staging -e image_sha=sha256:...

# 6. Misma imagen a producción
ansible-playbook playbooks/deploy.yml -e env=production -e image_sha=sha256:...  # MISMO sha que el 4

# 7. CI/CD real
git tag v1.0.0 && git push github v1.0.0
```

Además, específico de este proyecto:

```bash
# Cero credenciales estáticas
gitleaks detect --source . --no-banner

# Cero misconfiguraciones IaC críticas/altas sin justificar
trivy config oms-platform/terraform --severity CRITICAL,HIGH

# Diferencias staging/producción — deben ser solo capacidad/endpoints
diff ansible/group_vars/staging.yml ansible/group_vars/production.yml
diff <(grep -v '^#' terraform/envs/staging.tfvars) <(grep -v '^#' terraform/envs/production.tfvars)
```

El detalle completo de cada corrida real (incluyendo las que fallaron primero y por qué) está en [`BITACORA-COMANDOS.md`](BITACORA-COMANDOS.md).

## Si te bloqueas

- Vuelve al vídeo correspondiente (mapeo en `Trabajo - enunciado.md` sección 7).
- Revisa primero `BITACORA-COMANDOS.md` — la inmensa mayoría de los problemas que este proyecto encontró de verdad (y su solución exacta) ya están documentados ahí.
