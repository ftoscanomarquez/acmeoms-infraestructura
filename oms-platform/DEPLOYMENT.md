# DEPLOYMENT.md — Cómo se despliega esta plataforma

Este documento describe el flujo operativo real de despliegue: Ansible manual, CI/CD automático, canary progresivo y rollback. Para la arquitectura de lo que se despliega, ver [`INFRA.md`](INFRA.md).

## Principio de diseño: Terraform provisiona, Ansible despliega

Terraform crea la infraestructura y declara la **forma inicial** de Cloud Run (cpu, memoria, min/max instancias — ver decisión #2 del [README](README.md)). Una vez que el servicio existe, `lifecycle.ignore_changes` en `terraform/modules/compute/main.tf` cede el control de la **imagen** y del **reparto de tráfico** exclusivamente a Ansible. Un `terraform apply` posterior a un despliegue real nunca revierte un deploy o un canary en curso.

## Despliegue manual con Ansible

### `deploy.yml` — desplegar un `image_sha` a un entorno

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook playbooks/deploy.yml -e env=staging -e image_sha=sha256:<64 hex chars>
```

Qué hace, en orden:

1. **Valida parámetros** (`env` en `{staging, production}`, `image_sha` con formato `sha256:[a-f0-9]{64}`).
2. **Lee `cpu`/`memory`/`min_instances`/`max_instances` desde Terraform** (`terraform init -reconfigure -backend-config=envs/{{ env }}.backend.hcl` + `terraform output -json`) — nunca los declara, solo los lee como fuente de verdad.
3. Ejecuta el rol `oms_cloud_run`, que decide si hace falta desplegar y/o redirigir tráfico (ver más abajo — es idempotente de verdad, no solo "vuelve a correr sin romper nada").
4. **Post-deploy**: obtiene la URL pública, hace `GET /health` con reintentos (hasta 6 intentos, 5s de espera entre cada uno — el tráfico puede tardar en propagarse tras un `update-traffic`), y notifica a Slack si `slack_webhook_url` está definido (condicional — este proyecto no tiene un workspace de Slack real asociado, se documenta explícitamente por qué).

### Por qué no se usan módulos `google.cloud.gcp_cloudrun_*`

La rúbrica del enunciado pide explícitamente usar esos módulos. Se verificó exhaustivamente (`ansible-doc -l`, `ansible-galaxy collection list`, inspección directa de los `.py` de la colección `google.cloud` v1.10.2 instalada) que **no existen** — esa colección solo trae módulos para `runtimeconfig`, un servicio GCP completamente distinto. Es una laguna real y documentada del ecosistema, no una versión desactualizada de este proyecto. Se usa `ansible.builtin.command`/`shell` contra `gcloud run`, con una lógica de idempotencia diseñada a mano (ver siguiente sección) — documentado con el mismo detalle en `ansible/roles/oms_cloud_run/tasks/main.yml`.

### Cómo el rol `oms_cloud_run` logra idempotencia real

Idempotencia real significa: correr el mismo comando dos veces seguidas produce `changed=0` la segunda vez, **incluso si lo único que cambió es la capacidad, no la imagen**. El rol compara 4 campos, no solo 1:

1. Lee el estado actual declarado (`gcloud run services describe --format=value(...)`, imagen + cpu + memoria + max_instances) y calcula `needs_deploy` comparando los 4 contra los valores objetivo.
2. **Por separado**, lee cuál es la revisión que realmente recibe el 100% del tráfico ahora mismo (`status.traffic[]`, no la spec declarada) y su imagen real, calculando `needs_traffic_update`. Este segundo chequeo existe porque un hallazgo real mostró que ambos pueden divergir: tras un rollback de prueba, la spec declarada seguía "pareciendo correcta" (nadie la tocó) pero el tráfico real apuntaba a otra revisión — con solo `needs_deploy` como criterio, ese desalineamiento habría quedado sin corregir de forma silenciosa.
3. Si `needs_deploy`: despliega con `--no-traffic --tag=rev-<sha-corto>` (nunca manda tráfico de golpe a la revisión nueva) y espera con `until`/`retries` a que `status.conditions[0].status == "True"`.
4. Redirige tráfico con `--to-tags` (si acaba de desplegar, usa el tag recién asignado) o `--to-revisions` (si la revisión ya existía de antes, ej. tras un rollback manual reciente).

### `rollback.yml` — volver a la revisión anterior

```bash
ansible-playbook playbooks/rollback.yml -e env=production
```

Encuentra la revisión activa real (`status.traffic[]` filtrando `percent == 100`, **no** el orden de creación — un hallazgo real mostró que "la más recientemente creada" puede no ser la que recibe tráfico si hay una revisión desplegada con `--no-traffic` esperando promoción), valida que exista **exactamente una** con el 100%, cruza su posición en `gcloud run revisions list` (que sí ordena por fecha) para encontrar la N-1 respecto a la activa, y le asigna el 100% del tráfico con `--to-revisions=<N-1>=100`.

### `promote-canary.yml` — subir el canary de producción sin llegar al 100% de golpe

```bash
ansible-playbook playbooks/promote-canary.yml -e env=production -e target_percent=40
```

Complementario a `rollback.yml`: en vez de revertir, sube el tráfico del canary ya desplegado. Rango válido de `target_percent`: **11 a 100** — nunca ≤10 (el pipeline ya deja el canary ahí; pedir menos o igual sería no hacer nada) ni >100. Identifica el canary como la revisión más recientemente creada, cruzada con su porcentaje de tráfico actual (si es menor a 100%, es el canary). Compone `--to-revisions=<canary>=<target>,<otra>=<100-target>` en una sola llamada — un hallazgo real mostró que `gcloud run services update-traffic` con solo la revisión parcial, sin mencionar la otra, falla con `Every target with traffic is updated but 100% of traffic has not been specified`; Cloud Run **no** reparte el resto automáticamente.

**Nota de diseño conocida, no bloqueante**: si en un momento dado hay más de 2 revisiones con algún porcentaje de tráfico simultáneo (residuo de rondas de pruebas previas), el playbook toma la *primera* revisión "no-canary" que encuentra en el listado (`head -n1`), no necesariamente la que tiene más tráfico real entre ellas — el resultado final en porcentajes es siempre correcto (suma 100%), pero la revisión concreta que "absorbe" el resto podría no ser la más relevante. Ver `RETROSPECTIVA.md`.

## CI/CD real — `.github/workflows/ci-cd.yml`

Vive en la **raíz** del repositorio (no en `oms-platform/`) porque GitHub Actions solo detecta workflows ahí. Cuatro jobs:

```
push a main/PR          push de tag v*
      │                        │
      ▼                        ▼
   ┌──────┐              ┌──────────┐
   │  ci  │─────────────▶│  build   │  (solo si es tag v*)
   └──────┘   needs       └────┬─────┘
                                │ needs
                                ▼
                        ┌───────────────┐
                        │ deploy-staging│  (automático, sin aprobación)
                        └───────┬───────┘
                                │ needs
                                ▼
                     ┌────────────────────┐
                     │ deploy-production  │  ← environment: production
                     │  (canary 10%)      │    (gate manual, requiere aprobación)
                     └────────────────────┘
```

- **`ci`** (todo push/PR): lint del Dockerfile (`hadolint`), build de prueba en matriz (`22-alpine`/`20-alpine`, sin push), `terraform fmt -check` + `validate`, **Trivy `config`** contra Terraform (bloquea CRITICAL/HIGH), `gitleaks` (cero credenciales estáticas — penalización explícita del enunciado), y un paso de **SonarCloud cableado pero apagado a propósito** (`if: vars.SONAR_HOST_URL != ''`) — ver `OBSERVABILIDAD.md`.
- **`build`** (solo tag `v*`): build real + push a Artifact Registry de **staging**, **Trivy `image`** sobre la imagen ya subida (con `.trivyignore` documentado para los CVEs heredados de `node:22-alpine` que no son responsabilidad del proyecto), y **firma keyless con Cosign** (sin clave privada — reusa el mismo token OIDC de GitHub Actions). Ver `CERTIFICADOS.md` para el detalle de WIF y Cosign.
- **`deploy-staging`** (automático): autentica vía WIF de staging, instala Terraform (necesario para el pre-task de `deploy.yml`), verifica la firma con `cosign verify` antes de desplegar, corre `ansible-playbook deploy.yml -e env=staging`.
- **`deploy-production`** (`environment: production`, requiere aprobación manual en GitHub): **promociona la misma imagen por digest** (nunca reconstruye — `docker pull` de staging + `docker tag`+`push` a producción), copia la firma original con `cosign copy --only=sig` (la firma es un artefacto adjunto al registro donde se creó, no viaja con un simple `push`), verifica de nuevo la firma ya en el registro de producción, y despliega con Ansible dejando el canary real al 10%.

### Segundo workflow — `canary-decision.yml`

`ci-cd.yml` deja el canary en 10% y se detiene ahí a propósito — subirlo o revertirlo es una decisión humana explícita, nunca automática. `canary-decision.yml`, disparado solo por `workflow_dispatch` (nunca por push/tag), ofrece:

- **`promote`** con `target_percent` (11–100, validado también en el propio YAML como primera línea de defensa barata, antes de gastar minutos de runner) → corre `promote-canary.yml`.
- **`rollback`** → corre `rollback.yml`.

Ambos jobs mantienen `environment: production` — doble control (elección explícita en el dropdown + aprobación humana en GitHub) aunque sea parcialmente redundante, decisión consciente documentada en el README.

## Verificación real de un ciclo completo (evidencia)

Ejecutado de punta a punta contra `acmeoms-production-fatm` real, con un build nuevo (`v1.1.0`, bump de versión sin riesgo `0.2.0`→`0.3.0`):

1. `ci-cd.yml` corrió completo: `ci` → `build` (Trivy + Cosign) → `deploy-staging` → aprobación manual → `deploy-production`, dejando el canary real al 10% (`oms-production-00017-huk`).
2. `canary-decision.yml` (`promote`, `target_percent=50`) promovió el canary a 50%, verificado contra la API real de Cloud Run.
3. Un segundo `canary-decision.yml` (`promote`, `target_percent=100`) dejó producción en estado limpio: una sola revisión con el 100% del tráfico real, verificado con `curl` al healthcheck (`{"status":"ok","version":"0.3.0"}`) y con la API de Cloud Run.

El detalle completo, incluyendo los 2 hallazgos reales que aparecieron y se corrigieron durante esta verificación (un `attribute_condition` de WIF que no contemplaba `workflow_dispatch`, y un bug de `promote-canary.yml` con 3 revisiones activas simultáneas), está en `BITACORA-COMANDOS.md` § 6.21.
