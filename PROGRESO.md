# PROGRESO — Trabajo final Bloque 4 · Plataforma e infraestructura (AcmeOMS)

> **Propósito de este archivo:** es el punto de retomada de la sesión de trabajo con Claude Code. Si se corta la sesión (luz, cierre de la app, etc.), lo primero que hay que leer es este archivo: dice en qué fase estamos, qué está hecho, qué falta y cuál es el siguiente paso concreto.
>
> **Complementa a:** [`oms-platform/BITACORA-COMANDOS.md`](oms-platform/BITACORA-COMANDOS.md) — ahí va el detalle de cada comando ejecutado (qué hace, por qué, qué salida dio) y el registro de errores/hallazgos con su solución. Este archivo (`PROGRESO.md`) es el resumen de alto nivel; la bitácora de comandos es el detalle técnico reproducible.

---

## 📍 Estado actual

**Fase en curso:** Fase 1 — Terraform: red y datos (3 de 6 puntos completos)
**Último hito completado:** Módulos `network` y `database` completos y validados — juntos, sin conflictos entre sí (`terraform validate` conjunto desde la raíz solo mostró errores en `compute`, que aún no se toca, confirmando que `network`+`database` están correctos). En `database` se resolvió el TODO crítico de seguridad (password en texto plano → generada con `random_password` + guardada en Secret Manager) y se agregaron 3 `database_flags` de logging. Ver `oms-platform/BITACORA-COMANDOS.md` § Fase 1 para el detalle técnico completo.
**Siguiente paso concreto:** Configurar el backend `gcs` real en `terraform/main.tf` (descomentar y completar con el bucket de staging), ejecutar el primer `terraform init` con backend real + `terraform plan -var-file=envs/staging.tfvars`, y evaluar si hace falta completar algo de `compute`/`iam` antes o si el plan ya puede limitarse a `network`+`database`.

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

### Fase 1 — Terraform: red y datos

- [x] Completar módulo `network` (subredes multi-zona → reinterpretado como segmentación por propósito con subred `connector`; Cloud NAT; 3 reglas de firewall) — `terraform validate` exitoso en aislado
- [x] `terraform validate` de network + database juntos desde la raíz (sin backend) → sin errores entre ambos (los únicos errores son en `compute`, pendiente de Fase 2)
- [x] Completar módulo `database` (password vía `random_password` + Secret Manager — ya no texto plano; 3 `database_flags` de logging)
- [ ] `terraform plan` con network + database (requiere backend gcs configurado y un `.tfvars`)
- [ ] Primer `terraform apply` real a staging (network + database)
- [ ] Verificar recursos creados en consola GCP

### Fase 2 — Terraform: cómputo e IAM

- [ ] Completar módulo `compute` (probes, VPC connector, certificado SSL + proxy HTTPS + forwarding rule)
- [ ] Completar módulo `iam` (roles mínimos del SA de CI/CD)
- [ ] `terraform apply` completo a staging
- [ ] Verificar recursos en consola GCP
- [ ] Segundo `terraform plan` → confirmar "No changes" (idempotencia)

### Fase 3 — Docker + primer despliegue manual

- [ ] Completar `Dockerfile` (labels OCI reales, SHA de git real)
- [ ] Build local de la imagen
- [ ] Push manual a Artifact Registry → obtener primer `image_sha` real
- [ ] Verificar `docker run` local + healthcheck

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

---

## 📚 Referencias rápidas

- Enunciado: [`Trabajo - enunciado.md`](Trabajo%20-%20enunciado.md)
- Arquitectura origen (no editar): [`anexo-arquitectura/`](anexo-arquitectura/)
- Esqueleto a completar: [`oms-platform/`](oms-platform/)
- Los 7 comandos de verificación: sección 4 del enunciado
- Rúbrica: sección 5 del enunciado (100 pts + bonus sección 6)
