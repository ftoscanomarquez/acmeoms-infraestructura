# PROGRESO — Trabajo final Bloque 4 · Plataforma e infraestructura (AcmeOMS)

> **Propósito de este archivo:** es el punto de retomada de la sesión de trabajo con Claude Code. Si se corta la sesión (luz, cierre de la app, etc.), lo primero que hay que leer es este archivo: dice en qué fase estamos, qué está hecho, qué falta y cuál es el siguiente paso concreto.
>
> **Complementa a:** [`oms-platform/BITACORA-COMANDOS.md`](oms-platform/BITACORA-COMANDOS.md) — ahí va el detalle de cada comando ejecutado (qué hace, por qué, qué salida dio) y el registro de errores/hallazgos con su solución. Este archivo (`PROGRESO.md`) es el resumen de alto nivel; la bitácora de comandos es el detalle técnico reproducible.

---

## 📍 Estado actual

**Fase en curso:** ✅ Fases 1, 2 y 3 COMPLETAS → arrancando Fase 4 (Ansible: staging)
**Último hito completado:** **Los 38 recursos totales del proyecto están aplicados y verificados funcionalmente en GCP staging real** (`acmeoms-staging-fatm`): `network` (10) + `database` (7) + `compute` (10, incluye Artifact Registry y el binding IAM público) + `iam` (11). Cloud Run público y accesible: `https://oms-staging-7ifhynkuua-ey.a.run.app`. Load Balancer con IP fija `136.68.140.101` (certificado SSL en `PROVISIONING` hasta tener dominio real). Se resolvieron **7 hallazgos reales** durante el proceso (ver `BITACORA-COMANDOS.md` para el detalle completo de cada uno): 2 APIs de GCP faltantes en la Fase 0 (`servicenetworking`, `vpcaccess`), una condición de carrera de Terraform (`depends_on` explícito), un recurso creado a mano corregido a Terraform (Artifact Registry, señalado correctamente por el usuario), un problema de credenciales Docker en WSL (helper `.cmd` de Windows incompatible, resuelto con `docker-credential-gcr` nativo), una política IAM de Cloud Run vacía (agregado `roles/run.invoker` para `allUsers`), y el hallazgo más sutil: **`/healthz` es interceptado por Google Front End antes de llegar a Cloud Run** — se renombró el endpoint a `/health` en todo el proyecto (`server.js`, `Dockerfile`, Terraform, Ansible).
**Siguiente paso concreto:** Fase 4 (Ansible: staging) — completar `deploy.yml`/`rollback.yml`/el role `oms_cloud_run`, y ejecutar el primer despliegue real con el `image_sha` corregido (`sha256:fcd5c9483453625e40a4989a2edeee82a9ce6dbc78cef6c54ceabf5bcec82b25`) para que `/health` sirva la respuesta correcta (`{"status":"ok"}`) en vez del contenido de la imagen anterior.

---

## 🧭 Decisiones ya tomadas (no reabrir sin motivo)

| # | Decisión | Motivo |
|---|----------|--------|
| 1 | Carpeta de trabajo: **`oms-platform/`** (no se crea `AcmeOMS/`) | El enunciado (`Trabajo - enunciado.md`, sección 4) define el árbol de entregables explícitamente dentro de `oms-platform/`. El aviso "el dominio es OMS (AcmeOMS)" se refiere al dominio de negocio a documentar, no al nombre de la carpeta. |
| 2 | El nombre **AcmeOMS** se usa en documentación, labels de recursos GCP y tags — no como carpeta | Coherencia con el dominio del enunciado sin desviarse del árbol de entregables. |
| 3 | Se ejecuta **infraestructura real en GCP** (no solo `plan`/`validate`) | El usuario confirmó que quiere cumplir los 7 comandos de verificación del enunciado contra GCP real, usando capa gratuita + créditos de $300/90 días para lo que no tenga free tier (ej. Cloud CDN, Load Balancer). |
| 4 | **Doble remoto de Git sobre el mismo repo local** — `origin` = GitLab (`gitlab.codecrypto.academy`, entrega/evaluación), nuevo remoto `github` = repo nuevo en GitHub (solo para ejecutar el pipeline `.github/workflows/ci-cd.yml` con WIF de GitHub) | El enunciado pide literalmente el archivo `.github/workflows/ci-cd.yml` y WIF de GitHub (`issuer_uri = "https://token.actions.githubusercontent.com"`, ya está así en `terraform/modules/iam/main.tf`). El código de entrega sigue viviendo y versionándose en GitLab; el pipeline real se dispara con `git push github <rama o tag>`. Sin carpetas duplicadas, sin perder contexto. |
| 5 | Se intentan **los 5 bonus** del enunciado: Multi-region DR (+10), Cloud CDN políticas finas (+5), Bastion VM + Ansible + Datadog (+10), CMEK propia (+5), documentación de migración expand-and-contract (+5) | Decisión explícita del usuario. Se abordan en la Fase 7, después de asegurar la rúbrica base (100 pts), para no arriesgar la base por perseguir extras. |
| 6 | **Ambos proyectos GCP (staging y producción) se crean desde el inicio** (Fase 0), no se difiere la creación de producción | Alineado con el enunciado (son proyectos GCP distintos) y evita volver atrás en la Fase 5. |
| 7 | CMEK se implementa en la **Fase 7 (bonus)**, no adelantado a la Fase 1-2 de Terraform | Mantener la base (módulos `network`/`database`) simple primero; añadir CMEK después como extensión sobre lo ya validado. |
| 8 | Bitácora de estado: **`PROGRESO.md`** (raíz del repo, este archivo) | Fácil de encontrar al retomar sesión. |
| 9 | Bitácora de comandos: **`oms-platform/BITACORA-COMANDOS.md`** | Vive junto al resto de documentación técnica del entregable. Debe registrar TODOS los comandos ejecutados (qué hacen, por qué, cómo funcionan) y el detalle del flujo GitHub/GitLab, para poder reconstruir todo manualmente sin depender de esta sesión. |
| 10 | Todo el trabajo (chat, documentación, mensajes de commit, comentarios de progreso) **en español** | Preferencia explícita del usuario. |

---

## 🗺️ Plan por fases

### Fase 0 — Cuentas, accesos y doble remoto ✅ COMPLETA

- [x] Crear repo nuevo y vacío en GitHub (`acmeoms-infraestructura`)
- [x] `git remote add github <url>` sobre este mismo repo local (sin tocar `origin`)
- [x] Confirmar que `PROGRESO.md` y `BITACORA-COMANDOS.md` están creados y en uso
- [x] Activar "Comenzar gratis" en GCP (crédito Free Trial: 100% disponible, $5,089.20)
- [x] Crear proyecto GCP de staging (`acmeoms-staging-fatm`)
- [x] Crear proyecto GCP de producción (`acmeoms-production-fatm`)
- [x] Instalar/verificar herramientas locales: `gcloud` 585.0.0 (Windows), `terraform` 1.15.8 (WSL/Ubuntu), `ansible-core` 2.20.1 (WSL/Ubuntu), `docker` 29.8.0, Python 3.14.4 (WSL/Ubuntu) — todas cumplen los mínimos del README
- [x] `gcloud auth login` + `gcloud auth application-default login` (con quota project `acmeoms-staging-fatm`)
- [x] Habilitar APIs necesarias en ambos proyectos: compute, sqladmin, run, redis, secretmanager, iamcredentials, artifactregistry (cloudkms pendiente para cuando se implemente el bonus CMEK en Fase 7)
- [x] Crear bucket GCS de estado remoto de Terraform — uno por proyecto: `gs://acmeoms-staging-fatm-tfstate` y `gs://acmeoms-production-fatm-tfstate` (europe-west3, versionados)

### Fase 1 — Terraform: red y datos ✅ COMPLETA

- [x] Completar módulo `network` (subredes multi-zona → reinterpretado como segmentación por propósito con subred `connector`; Cloud NAT; 3 reglas de firewall) — `terraform validate` exitoso en aislado
- [x] `terraform validate` de network + database juntos desde la raíz (sin backend) → sin errores entre ambos
- [x] Completar módulo `database` (password vía `random_password` + Secret Manager — ya no texto plano; 3 `database_flags` de logging)
- [x] `terraform plan` con network + database → limpio, 17 recursos
- [x] Primer `terraform apply` real a staging (network + database) — 17/17 recursos creados (en 3 tandas por 2 hallazgos resueltos: API `servicenetworking` faltante, condición de carrera con `depends_on`)
- [x] Verificar recursos creados: por API directa (`gcloud list`) y URLs de consola documentadas

### Fase 2 — Terraform: cómputo e IAM ✅ COMPLETA

- [x] Completar módulo `compute` (probes → `/health` tras hallazgo de GFE, VPC connector → `/28` tras hallazgo de netmask, certificado SSL + proxy HTTPS + forwarding rule, Artifact Registry, binding IAM público)
- [x] Completar módulo `iam` (roles mínimos del SA de CI/CD: `run.developer`, `iam.serviceAccountUser`, `artifactregistry.writer`+`reader`)
- [x] `terraform apply` completo a staging — 38/38 recursos totales aplicados (múltiples hallazgos resueltos: API `vpcaccess` faltante, connector residual en ERROR, lock de estado huérfano tras corte de sesión, import del connector, IAM vacío, endpoint `/healthz` interceptado por GFE)
- [x] Verificar recursos en consola GCP — Cloud Run público y funcional (`curl /health` → 200 OK)
- [ ] Segundo `terraform plan` → confirmar "No changes" (pendiente de re-verificar tras los últimos cambios de esta sesión)

### Fase 3 — Docker + primer despliegue manual ✅ COMPLETA (adelantada durante la Fase 2)

- [x] Completar `Dockerfile` (labels OCI reales con `ARG GIT_SHA`/`BUILD_DATE`, endpoint `/health`)
- [x] Build local de la imagen (placeholder mínimo `server.js`, NO es la app OMS real — ver nota en el propio código)
- [x] Push manual a Artifact Registry → `image_sha` real obtenido: `sha256:fcd5c9483453625e40a4989a2edeee82a9ce6dbc78cef6c54ceabf5bcec82b25`
- [x] Verificar `docker run` local + healthcheck (probado antes del push)

> Nota: el DESPLIEGUE de esta imagen a Cloud Run (que la ponga a servir tráfico real) no es un paso de la Fase 3 — es el contenido completo de la Fase 4 (Ansible), donde el `image_sha` se pasa como parámetro `-e` al playbook, no editando archivos. Recuerda que Terraform ignora deliberadamente los cambios de imagen (`lifecycle.ignore_changes`) desde el primer `apply` de Cloud Run.

### Fase 4 — Ansible: staging

- [ ] Completar `deploy.yml` (healthcheck post-deploy, notificación)
- [ ] Completar `rollback.yml` (listar revisiones, redirigir tráfico)
- [ ] Completar role `oms_cloud_run` (traffic-splitting real, espera a `Ready`)
- [ ] Ejecutar `ansible-playbook deploy.yml -e env=staging -e image_sha=...`
- [ ] Repetir el mismo comando → verificar `changed=0`

### Fase 5 — Producción

- [ ] `terraform apply -var-file=envs/production.tfvars`
- [ ] `ansible-playbook deploy.yml -e env=production -e image_sha=<mismo SHA que staging>`
- [ ] Verificar canary al 10% en producción

### Fase 6 — CI/CD (GitHub Actions + WIF)

- [ ] Crear `.github/workflows/ci-cd.yml` (build → test → push imagen → captura digest → despliegue vía Ansible/gcloud con WIF)
- [ ] Push de tag `v1.0.0` al remoto `github`
- [ ] Verificar que el pipeline corre y el mismo SHA llega a ambos entornos

### Fase 7 — Bonus

- [ ] CMEK propia (Cloud SQL + un bucket)
- [ ] Cloud CDN políticas finas (extiende módulo `compute`)
- [ ] Multi-region DR (`europe-central2`) + runbook de failover
- [ ] Bastion VM + Ansible + Datadog + inventario dinámico por label
- [ ] Documentación de migración expand-and-contract (solo prosa, ejemplo con `orders.orders`)

### Fase 8 — Documentación final y cierre

- [ ] README con sección "Decisiones" (3 trade-offs + 3 cambios al borrador de IA)
- [ ] `INFRA.md`
- [ ] `OBSERVABILIDAD.md`
- [ ] `CERTIFICADOS.md` (evaluar si aplica tal cual lo define toscaprompt, dado que aquí el TLS lo gestiona el Load Balancer de GCP, no Traefik/mkcert)
- [ ] `DEPLOYMENT.md`
- [ ] `DIAGRAMAS.md`
- [ ] `RETROSPECTIVA.md`
- [ ] Verificación final de los 7 comandos del enunciado (sección 4)
- [ ] Decidir si se destruye la infraestructura (`terraform destroy` + limpieza) para no agotar crédito, dejando todo documentado para reconstruir

---

## ⚠️ Errores y hallazgos (registro rápido — el detalle va en BITACORA-COMANDOS.md)

_(vacío por ahora — se va llenando conforme avancemos)_

| Fecha | Fase | Problema encontrado | Cómo se resolvió | Detalle completo |
|-------|------|---------------------|-------------------|-------------------|
| 2026-09-20 | Fase 0 | `gcloud` no detectado en la sesión de Bash tras instalar el SDK (problema de PATH) | `export PATH=...` + persistido en `~/.bashrc`, sin reiniciar VS Code | BITACORA-COMANDOS.md § 0.5 |
| 2026-09-20 | Fase 0 | Docker Desktop no arrancaba: "WSL integration with distro 'Ubuntu' unexpectedly stopped" tras actualización de Windows | `wsl --shutdown` + reabrir Docker Desktop | BITACORA-COMANDOS.md § 0.5b |
| 2026-09-20 | Fase 0 | `gcloud auth application-default login --no-launch-browser`: primero `Scope has changed` (consentimiento incompleto), luego `Error 400: Missing required parameter: redirect_uri` al usar mal el modo `--remote-bootstrap` | Usar el flujo normal sin `--no-browser` (WSL2 reenvía `localhost:8085` automáticamente al navegador de Windows) | BITACORA-COMANDOS.md § 0.6 |
| 2026-09-21 | Fase 1 | `terraform apply` falló: `SERVICE_NETWORKING_NOT_ENABLED` | Faltaba habilitar `servicenetworking.googleapis.com` en la Fase 0 — corregido en ambos proyectos | BITACORA-COMANDOS.md § 1.4 |
| 2026-09-21 | Fase 1 | Condición de carrera: Cloud SQL/Redis se creaban en paralelo con la conexión de peering, sin dependencia declarada | `depends_on` explícito entre módulos (nuevo output `private_vpc_connection_id`) | BITACORA-COMANDOS.md § 1.4 |
| 2026-09-21 | Fase 2 | `terraform apply` falló: `Serverless VPC Access API has not been used` | Faltaba habilitar `vpcaccess.googleapis.com` — corregido en ambos proyectos | BITACORA-COMANDOS.md § 2.5 |
| 2026-09-21 | Fase 2 | VPC Connector rechazado: "Subnets used for VPC connectors must have a netmask of 28" | Subred `connector` redimensionada de `/20` a `/28` (caso real de VLSM) | BITACORA-COMANDOS.md § 2.5 |
| 2026-09-21 | Fase 2 | Corte de sesión a media ejecución dejó un connector residual en GCP y un lock de estado huérfano | Eliminación manual del residual + `terraform force-unlock` + `terraform import` del connector real | BITACORA-COMANDOS.md § 2.5 |
| 2026-09-21 | Fase 2 | Artifact Registry creado inicialmente a mano (fuera de Terraform) — **señalado correctamente por el usuario** | Revertido y declarado como `google_artifact_registry_repository` en Terraform | BITACORA-COMANDOS.md § 2.6 |
| 2026-09-21 | Fase 3 | `docker push` fallaba: helper `docker-credential-gcloud` es un `.cmd` de Windows, incompatible con Docker en WSL | Instalado `docker-credential-gcr` (binario nativo de Linux, sin `sudo`) | BITACORA-COMANDOS.md § 3.1 |
| 2026-09-21 | Fase 2 | Cloud Run con política IAM vacía → 403/404 en toda ruta | `roles/run.invoker` para `allUsers` vía Terraform | BITACORA-COMANDOS.md § 3.3 |
| 2026-09-21 | Fase 2 | `/healthz` siempre 404 (nunca en logs) aunque `/` funcionaba — Google Front End intercepta esa ruta antes de Cloud Run | Renombrado el endpoint a `/health` en todo el proyecto | BITACORA-COMANDOS.md § 3.3 |

---

## 📚 Referencias rápidas

- Enunciado: [`Trabajo - enunciado.md`](Trabajo%20-%20enunciado.md)
- Arquitectura origen (no editar): [`anexo-arquitectura/`](anexo-arquitectura/)
- Esqueleto a completar: [`oms-platform/`](oms-platform/)
- Los 7 comandos de verificación: sección 4 del enunciado
- Rúbrica: sección 5 del enunciado (100 pts + bonus sección 6)
