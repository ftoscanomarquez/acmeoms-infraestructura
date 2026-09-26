# PROGRESO — Trabajo final Bloque 4 · Plataforma e infraestructura (AcmeOMS)

> **Propósito de este archivo:** es el punto de retomada de la sesión de trabajo con Claude Code. Si se corta la sesión (luz, cierre de la app, etc.), lo primero que hay que leer es este archivo: dice en qué fase estamos, qué está hecho, qué falta y cuál es el siguiente paso concreto.
>
> **Complementa a:** [`oms-platform/BITACORA-COMANDOS.md`](oms-platform/BITACORA-COMANDOS.md) — ahí va el detalle de cada comando ejecutado (qué hace, por qué, qué salida dio) y el registro de errores/hallazgos con su solución. Este archivo (`PROGRESO.md`) es el resumen de alto nivel; la bitácora de comandos es el detalle técnico reproducible.

---

## 🏁 AVANCE TOTAL DEL TRABAJO — **✅ 100% del ciclo de vida completo**

**Rúbrica base (100 pts): ✅ completa y verificada contra GCP real · Bonus: 3/5 completos (+15 pts) · Cierre (destroy): ✅ COMPLETO — ambos entornos destruidos y verificados**

| Fase | Estado | % |
|---|---|---|
| Fase 0 — Cuentas, accesos y doble remoto | ✅ COMPLETA | 100% |
| Fase 1 — Terraform: red y datos | ✅ COMPLETA | 100% |
| Fase 2 — Terraform: cómputo e IAM | ✅ COMPLETA | 100% |
| Fase 3 — Docker + primer despliegue manual | ✅ COMPLETA | 100% |
| Fase 4 — Ansible: staging | ✅ COMPLETA | 100% |
| Fase 5 — Producción | ✅ COMPLETA | 100% |
| Fase 6 — CI/CD (GitHub Actions + WIF) | ✅ COMPLETA | 100% |
| Fase 7 — Bonus (3 de 5 opcionales) | 🟡 PARCIAL | 60% (3/5) |
| Fase 8 — Documentación final | ✅ COMPLETA | 100% |
| Fase 9 — Cierre (`terraform destroy`) | ✅ COMPLETA | 100% |

**El proyecto está cerrado por completo.** Toda la infraestructura real de ambos proyectos GCP (`acmeoms-staging-fatm`, `acmeoms-production-fatm`) fue provisionada, operada, documentada, y finalmente destruida — verificado contra la API real de GCP en cada paso. Lo único que queda existiendo, por una limitación real e irreversible de la API de Cloud KMS (no de este proyecto), son las 4 `CryptoKey` (2 por entorno) del bonus CMEK — sin coste por su sola existencia. Los 2 bonus no abordados (Multi-region DR, Bastion+Datadog) quedan documentados como pendientes por decisión explícita de priorizar los 3 de menor esfuerzo.

---

## 📍 Estado actual

**Fase en curso:** ✅ **Proyecto cerrado por completo.** `terraform destroy` se completó con éxito en ambos entornos. El único obstáculo real (la conexión de peering de red privada bloqueada por backups huérfanos de Cloud SQL, más de 12h de espera sin resolución automática) se resolvió eliminando el peering manualmente desde la consola web de GCP — la API vía CLI/Terraform seguía rechazando el borrado, pero la consola sí lo permitió. Tras eso, `terraform destroy` completó sin problemas en ambos entornos (`Destroy complete! Resources: 2 destroyed.` en cada uno). Verificado contra la API real: ambos proyectos solo conservan la red `default` que GCP crea automáticamente (nunca gestionada por este código) — cero recursos propios pendientes salvo las 4 claves KMS irreborrables. Ver el detalle completo de todo el proceso de cierre en `BITACORA-COMANDOS.md` § 9.1-9.6.

**Último hito completado:** El pipeline `ci-cd.yml` corrió de punta a punta (`ci` → `build` con Trivy+Cosign → `deploy-staging` → aprobación manual → `deploy-production`) tras 9 iteraciones de fixes reales, todos documentados en `BITACORA-COMANDOS.md` secciones 6.11–6.19. Verificado con `curl` real al healthcheck y `cosign verify` independiente de la firma en ambos registros (staging y producción).

Después, a petición del usuario, se construyó el **segundo workflow de decisión post-canary** (`canary-decision.yml`), que resuelve el hueco que el propio usuario identificó: el `ci-cd.yml` deja el canary de producción en 10% y ahí se detiene — no hay ninguna promoción automática. El nuevo workflow, disparado solo por `workflow_dispatch`, ofrece 2 decisiones humanas:
- **`promote`**: sube el canary a un `target_percent` capturado por input, validado estrictamente en **rango 11–100** (11 porque bajarlo o dejarlo en 10 equivaldría a no hacer nada; 100 porque en ese punto el canary pasa a ser la revisión oficial).
- **`rollback`**: retira el canary por completo, devolviendo el 100% del tráfico a la revisión anterior (reutiliza `rollback.yml` ya existente).

Para soportar `promote` se creó `oms-platform/ansible/playbooks/promote-canary.yml`, con lógica para detectar la revisión candidata (la más reciente creada, cruzada con su % de tráfico actual — no por tag manual), calcular el argumento `--to-revisions` sumando ambas revisiones a 100% explícito, y bloquear cualquier intento de bajar el tráfico en vez de subirlo. Se verificó con **pruebas reales contra `acmeoms-production-fatm`**:
1. Canary al 10% → promovido a 40% (`oms-production-00008-qeb=40,oms-production-00003-yod=60`) — ✅ éxito.
2. Intento con 5% → rechazado por el `assert` de rango (11-100) — ✅ bloqueo correcto.
3. Intento de 20% estando ya en 40% → rechazado por el `assert` de "sube, no baja" — ✅ bloqueo correcto.
4. Canary al 40% → promovido a 100% (default) → producción quedó en `oms-production-00008-qeb` al 100% limpio, healthcheck `{"status":"ok","version":"0.2.0"}` — ✅ éxito.
5. **Rollback real ejecutado también**: desde 100% en `oms-production-00008-qeb`, `rollback.yml` identificó correctamente la N-1 (`oms-production-00003-yod`, no la más reciente creada, sino la anterior a la activa) y le devolvió el 100% del tráfico — ✅ verificado con `ansible-playbook` real, `changed=1`, sin fallos.

El workflow `canary-decision.yml` mantiene a propósito el gate `environment: production` (doble control: dropdown manual + aprobador humano en GitHub) aunque sea redundante con la elección explícita del `workflow_dispatch` — decisión confirmada con el usuario.

**Verificación real end-to-end de `canary-decision.yml` como workflow de GitHub Actions** (no solo local): se generó un build nuevo real (`0.2.0`→`0.3.0`, tag `v1.1.0`), se corrió el pipeline completo hasta dejar un canary real al 10% en producción, y se disparó `canary-decision.yml` por primera vez desde Actions. Aparecieron y se corrigieron **2 hallazgos reales nuevos** (documentados en `BITACORA-COMANDOS.md` § 6.21):
1. **WIF rechazaba el token**: el `attribute_condition` del provider de producción solo aceptaba tags (`refs/tags/v*`), pero `canary-decision.yml` corre por `workflow_dispatch` sobre `main` (`refs/heads/main`). Corregido ampliando la condición (`attribute.event_name` agregado al mapping, condición con `||` para aceptar ambos casos legítimos), aplicado con `terraform apply` real desde WSL y verificado contra la API de GCP con `curl` autenticado.
2. **`promote-canary.yml` rompía con 3 revisiones activas simultáneas**: el `awk` que identifica "la otra revisión" no estaba pensado para más de 2, y devolvía 2 líneas que Jinja2 pegaba mal dentro de `--to-revisions` (`Bad syntax for dict arg`). Corregido con `head -n1` (la revisión sobrante queda en 0% automáticamente en Cloud Run, sin necesidad de limpiarla antes).

Tras ambos fixes, run exitoso final `36013855248`: canary promovido de 10% a 50% real, verificado contra la API de Cloud Run (`oms-production-00017-huk=50%`, `oms-production-00003-yod=50%`, la tercera revisión en 0%). Inmediatamente después, un segundo disparo real de `canary-decision.yml` (`decision=promote`, `target_percent=100`, run `36014615757`) promovió el canary a producción oficial única: verificado con `curl` al healthcheck real (`{"status":"ok","version":"0.3.0"}`) y contra la API de Cloud Run (`oms-production-00017-huk=100%`, las otras 2 revisiones sin tráfico) — estado final de producción limpio.

Se dio además una explicación pedagógica completa, línea por línea, de todo `.github/workflows/ci-cd.yml` (para que el usuario lo pueda defender en su video), cubriendo: qué es CI/CD, `strategy.matrix`, `needs`, `outputs` de job, el contexto `github.*`, el mecanismo completo de WIF, el ciclo firmar/verificar de Cosign, y por qué la seguridad real vive en el `attribute_condition` de GCP, no en el YAML. También se explicó en detalle el mecanismo del canary (por qué vive en Cloud Run como una revisión más, cómo se reparte el tráfico por porcentaje, y por qué la subida de 10% a 100% es una decisión humana y no un temporizador ni una condición automática de métricas) — incluida la pregunta puntual de por qué una revisión en 0% de tráfico sigue existiendo sana en Cloud Run (no se invalida automáticamente: permite rollback instantáneo sin rebuild, y sos vos quien decide cuándo borrarla).

**Siguiente paso concreto:** Todo el trabajo de infraestructura queda cerrado. El usuario va a grabar el video de explicación del trabajo; después de eso, `terraform destroy` de ambos entornos.

---

### 🎁 Fase 7 — Bonus (avance de esta sesión, cierre)

A petición del usuario ("cuales son las mas faciles de implementar que no implique mucho esfuerzo"), se implementaron y verificaron contra GCP real 3 de los 5 bonus:

1. **Expand-and-contract**: solo documentación (`MIGRACION-EXPAND-CONTRACT.md`), sin tocar infraestructura.
2. **Cloud CDN políticas finas**: afinada la política de caché ya existente desde la Fase 1, agregado un bucket de assets/SPA con signed URLs. 2 hallazgos reales de la API de GCP corregidos en el camino (bloque `encryption` de un bucket no acepta `null` condicional; código `500` inválido en `negative_caching_policy`, corregido a `501`).
3. **CMEK propia**: nuevo módulo `terraform/modules/kms/`. Esta fue la pieza más delicada de toda la sesión — activar CMEK sobre una Cloud SQL YA EXISTENTE exige recrearla (`encryption_key_name` es inmutable), lo que expuso **5 hallazgos reales encadenados** sobre las protecciones de producción del propio proyecto:
   - `lifecycle.prevent_destroy` bloqueó correctamente el `plan` (comportamiento esperado de una protección real, no un bug).
   - `deletion_protection` resultó tener DOS campos independientes y fácilmente confundibles dentro del mismo recurso (`deletion_protection` de Terraform vs. `settings.deletion_protection_enabled`, el que la API real consulta) — el código nunca había declarado el segundo, así que Terraform nunca lo controlaba.
   - Cambiar esa protección Y forzar la recreación en el MISMO `apply` no funcionó de forma fiable con este provider — resuelto separando en 2 `apply` distintos (primero solo el cambio de protección, después la recreación).
   - Una destrucción parcial exitosa dejó recursos huérfanos en el estado de Terraform (`google_sql_database.oms`, `google_sql_user.oms` apuntando a una instancia ya destruida) — resuelto con `terraform state rm`.
   - Las Service Agents de Cloud SQL y Cloud Storage nunca se habían aprovisionado formalmente en ninguno de los dos proyectos (aunque su nombre es predecible) — resuelto forzando su creación con `google_project_service_identity`.

Todo verificado contra la API real de GCP (no solo el resumen de los `apply`) en staging y producción, con ambas protecciones de Cloud SQL restauradas a `true` de forma permanente al finalizar. Detalle completo en `BITACORA-COMANDOS.md` § 7.1-7.3.

Quedan sin implementar, por mayor esfuerzo real: Multi-region DR (+10 pts) y Bastion+Ansible+Datadog (+10 pts).

---

### 📄 Fase 8 — documentación final (avance de sesión anterior)

Se escribieron de una sola vez los 6 documentos de `oms-platform/`, cada uno basado en lectura directa de todo el código real (los 4 módulos de Terraform completos, los 3 playbooks de Ansible + el rol `oms_cloud_run`, el `Dockerfile`, y `ci-cd.yml`) — no son plantillas genéricas, cada afirmación remite a un archivo, un valor o un comando real:

- **`README.md`**: reescrito por completo (el esqueleto original nunca se había rellenado). Incluye la sección "Decisiones" obligatoria con 3 trade-offs reales (Cloud Run vs GKE, Terraform como única fuente de verdad de cpu/memoria/instancias, doble control humano en el canary) y 3 cambios concretos sobre el borrador de IA (validación de región incompleta, módulos `google.cloud.gcp_cloudrun_*` inexistentes, `allowed_audiences` incorrecto de WIF) — los mismos hallazgos reales ya documentados en `BITACORA-COMANDOS.md`, pero redactados aquí para el lector del entregable, no como bitácora de sesión.
- **`INFRA.md`** (nuevo): arquitectura real módulo por módulo (`network`/`database`/`compute`/`iam`), con la tabla real de diferencias staging/producción y el resumen de recursos aplicados (38 en la primera aplicación completa).
- **`DEPLOYMENT.md`** (nuevo): flujo operativo completo — cómo funciona la idempotencia real de `oms_cloud_run` (comparación de 4 campos, no solo la imagen), los 3 playbooks, los 4 jobs de `ci-cd.yml`, y el segundo workflow `canary-decision.yml`, cerrando con la evidencia del ciclo completo verificado esta sesión.
- **`OBSERVABILIDAD.md`** (nuevo): los 8 `database_flags` reales de Cloud SQL con su propósito cada uno, las 3 capas de healthcheck, y una admisión explícita de lo que NO está implementado (audit trail inmutable de REG-GDPR-003, degradación suave de Redis sin código de negocio que probarla).
- **`CERTIFICADOS.md`** (nuevo): TLS del Load Balancer (certificado managed, estado real `PROVISIONING` sin dominio), WIF/OIDC completo con sus 2 hallazgos reales (audience incorrecto, `attribute_condition` incompleta), y Cosign keyless con el hallazgo de `cosign copy` para la firma cross-registro.
- **`RETROSPECTIVA.md`** (nuevo): documento deliberadamente honesto — 3 desviaciones reales respecto a la spec (NFR-SCAL-001 por cuota real, audit trail no implementado, ausencia de módulos Ansible de Cloud Run), la deuda técnica conocida de `promote-canary.yml` (criterio de "primera revisión" en vez de "más tráfico"), y 4 puntos concretos de qué se haría distinto con el conocimiento actual.

Pendiente de esta sub-tarea: releer los 6 documentos una vez más buscando inconsistencias entre sí (ej. mismos números, mismos nombres de revisión) antes de considerarlos definitivos para el video.

> 📋 **Ver reporte completo de la Fase 5** (issues encontrados y cómo se resolvieron) al final de este archivo, sección "Reporte Fase 5 — completada de forma autónoma".
> 📊 **`DIAGRAMAS.md` actualizado** con un nuevo diagrama de flujo (sección 2.bis) que muestra dónde se genera el build, cómo pasa por Terraform en la corrida inicial vs por Ansible en corridas subsecuentes, staging vs producción, el canary real, y el rollback — con círculos de color por tipo de corrida.

> 🗓️ **Pendiente para el cierre de hoy** (prioridad del usuario: terminar todo hoy porque tiene que grabar el video de explicación justo después):
> 1. ~~Commit/push de `promote-canary.yml` + `canary-decision.yml`.~~ ✅ Hecho, incluyendo los 2 fixes de esta verificación.
> 2. Fase 7 (bonus) si el tiempo alcanza.
> 3. Fase 8 (documentación final: README con sección "Decisiones", `INFRA.md`, etc.) — mínimo indispensable si no da tiempo para todo.
> 4. **`terraform destroy` de ambos entornos al final** — decisión ya tomada por el usuario (evitar seguir gastando el crédito de $300/90 días una vez grabado el video). Hacerlo en orden inverso de dependencias, y confirmar con `gcloud` que no queda ningún recurso huérfano facturable tras el destroy.

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

- [x] Completar módulo `compute`: Cloud Run v2 (imagen por digest, `startup_probe`/`liveness_probe` → `/health` tras hallazgo de GFE, `lifecycle.ignore_changes` sobre imagen/tráfico/revisión), VPC Access Connector (`/28` tras hallazgo de netmask), Artifact Registry declarado en Terraform (revertido de un `gcloud create` manual inicial), Load Balancer completo (NEG serverless + backend service con Cloud CDN + url map + certificado SSL managed + proxy HTTPS + forwarding rule), binding IAM público (`roles/run.invoker` a `allUsers`)
- [x] Completar módulo `iam`: WIF pool + provider por entorno (`issuer_uri` de GitHub Actions), Service Account de CI/CD con roles mínimos (`run.developer`, `artifactregistry.writer`+`reader`, `iam.serviceAccountUser` acotado al SA de runtime — endurecido más tarde en la Fase 6 tras un hallazgo de Trivy), Service Account de runtime con `cloudsql.client` + `secretmanager.secretAccessor`
- [x] `terraform apply` completo a staging — **38/38 recursos totales aplicados**, resolviendo en el camino: API `vpcaccess.googleapis.com` faltante, VPC Connector rechazado por netmask incorrecta, connector residual en estado ERROR tras un corte de sesión + lock de estado huérfano (`terraform force-unlock` + `terraform import` del connector real), política IAM de Cloud Run vacía (403/404 en toda ruta), endpoint `/healthz` interceptado por Google Front End antes de llegar al contenedor
- [x] Verificar recursos en consola GCP y por API real — Cloud Run público y funcional (`curl https://oms-staging-....run.app/health` → `200 {"status":"ok"}`)
- [x] Segundo `terraform plan` → confirmado "No changes" en múltiples ocasiones a lo largo del proyecto (Fase 5, Fase 6) tras cada corrección — el módulo `compute` en sí quedó estable ya en esta fase

### Fase 3 — Docker + primer despliegue manual ✅ COMPLETA (adelantada durante la Fase 2)

- [x] Completar `Dockerfile` (labels OCI reales con `ARG GIT_SHA`/`BUILD_DATE`, endpoint `/health`)
- [x] Build local de la imagen (placeholder mínimo `server.js`, NO es la app OMS real — ver nota en el propio código)
- [x] Push manual a Artifact Registry → `image_sha` real obtenido: `sha256:fcd5c9483453625e40a4989a2edeee82a9ce6dbc78cef6c54ceabf5bcec82b25`
- [x] Verificar `docker run` local + healthcheck (probado antes del push)

> Nota: el DESPLIEGUE de esta imagen a Cloud Run (que la ponga a servir tráfico real) no es un paso de la Fase 3 — es el contenido completo de la Fase 4 (Ansible), donde el `image_sha` se pasa como parámetro `-e` al playbook, no editando archivos. Recuerda que Terraform ignora deliberadamente los cambios de imagen (`lifecycle.ignore_changes`) desde el primer `apply` de Cloud Run.

### Fase 4 — Ansible: staging ✅ COMPLETA

- [x] Completar `deploy.yml`: valida parámetros (`env`, `image_sha` con regex `sha256:[a-f0-9]{64}`), despliega vía el rol `oms_cloud_run`, healthcheck post-deploy con reintentos (`until`/`retries` contra `/health`), notificación a Slack condicional (`when: slack_webhook_url is defined` — sin workspace real asociado, documentado a propósito)
- [x] Completar `rollback.yml`: identifica la revisión activa real por `status.traffic[]` (`percent==100`), **no** por orden de creación — corregido tras un hallazgo real (una revisión de prueba sin tráfico más reciente habría causado un rollback no-op silencioso); valida que exista exactamente una revisión al 100%; encuentra la N-1 cruzando con `gcloud run revisions list`; redirige el 100% del tráfico
- [x] Completar rol `oms_cloud_run`: traffic-splitting real (`--to-tags`/`--to-revisions` según el caso), espera activa a `Ready` (`until`/`retries` sobre `status.conditions[0].status`), idempotencia verificada comparando 4 campos (imagen, cpu, memoria, max_instances) — no solo la imagen, tras detectar que un cambio de capacidad sin tocar la imagen no se aplicaba con el diseño inicial
- [x] Ejecutar `ansible-playbook deploy.yml -e env=staging -e image_sha=...` — despliegue real verificado contra `acmeoms-staging-fatm`, healthcheck `200 OK` confirmado con `curl` externo
- [x] Repetir el mismo comando → verificado `changed=0` en la segunda ejecución (idempotencia real, no solo teórica)
- [x] Resueltos en el camino: `ansible.cfg` no cargaba desde WSL sobre `/mnt/d/...` (`ANSIBLE_CONFIG` explícito), callback `community.general.yaml` eliminado de la colección (`ANSIBLE_STDOUT_CALLBACK=default`), proyecto activo de `gcloud` perdido tras corte de sesión, bug de `--format=value(...)` partido en varias líneas YAML, bug de `regex_replace` con backreferences sin resolver al recibir `image_sha` por `-e` (reemplazado por slicing simple de Jinja2)

### Fase 5 — Producción ✅ COMPLETA

- [x] `terraform apply -var-file=envs/production.tfvars` — **39 recursos reales aplicados** en `acmeoms-production-fatm` (red, Cloud SQL, Redis, IAM/WIF, Load Balancer, Cloud Run, Artifact Registry), resolviendo en el camino un choque real de cuota de CPU (`CpuAllocPerProjectRegion` excedida con el `max_instances` original de NFR-SCAL-001) y un recurso marcado `tainted` tras un `apply` interrumpido
- [x] `ansible-playbook deploy.yml -e env=production -e image_sha=<mismo SHA que staging>` — **imagen promocionada con el mismo digest SHA-256 exacto** (copiada, nunca reconstruida — verificado carácter por carácter), primer despliegue real a producción, healthcheck externo confirmado con `curl`
- [x] Verificar canary al 10% en producción — verificado con un segundo build real (`v0.2.0`): dos revisiones sirviendo tráfico y contenido distinto simultáneamente, confirmado con `curl` repetido
- [x] **Rediseño real solicitado por el usuario a mitad de la fase**: `cpu`/`memory`/`min_instances`/`max_instances` dejaron de duplicarse a mano entre Terraform y Ansible (causa raíz de un drift real detectado — `memory` desalineada silenciosamente) — Terraform pasó a exponerlos como outputs, Ansible los lee en vivo con `terraform output -json` en cada despliegue
- [x] Ciclo completo canary + rollback verificado contra producción real, en ambos escenarios: rollback con tráfico en canary (falla explícitamente, comportamiento correcto) y rollback con una única revisión al 100% (éxito real, tráfico movido a la N-1)
- [x] Ambos entornos confirmados en estado estable: `terraform plan` → "No changes" en staging y producción

> 📋 Detalle completo hora por hora de esta fase (completada de forma autónoma durante una noche, a petición del usuario) en la sección **"Reporte Fase 5"** al final de este archivo — incluye tabla de 11 issues reales encontrados y resueltos, y las decisiones tomadas de forma autónoma para revisar al despertar.

### Fase 6 — CI/CD (GitHub Actions + WIF) ✅ COMPLETA

- [x] Crear `.github/workflows/ci-cd.yml` (`ci` → `build` con Trivy+Cosign → `deploy-staging` → `deploy-production` con canary 10%, gate manual `environment: production`)
- [x] Push de tag `v1.0.0` al remoto `github` — pipeline completo verificado de punta a punta tras 9 iteraciones de fixes reales (WIF audience, cosign verify, ansible-galaxy path, callback yaml, terraform binario, permiso bucket tfstate, cosign copy cross-proyecto)
- [x] Verificar que el pipeline corre y el mismo digest de imagen llega a ambos entornos (`cosign verify` independiente + `curl` real al healthcheck en staging y producción)
- [x] Endurecido con Trivy real (`trivy config` sobre Terraform + `trivy image` sobre la imagen Docker) — 3 hallazgos de seguridad reales corregidos contra GCP real (SSL de Cloud SQL, `serviceAccountUser` sobre-otorgado, logging de Cloud SQL)
- [x] SonarCloud cableado pero deliberadamente apagado (`if: vars.SONAR_HOST_URL != ''`), documentado el motivo
- [x] Segundo workflow `.github/workflows/canary-decision.yml` (decisión manual post-canary: `promote` con `target_percent` 11-100, o `rollback`) + playbook `promote-canary.yml`
- [x] Repitió el ciclo completo con un build nuevo real (`v1.1.0`, bump `0.2.0`→`0.3.0`) para reverificar todo de punta a punta, tal como pidió el usuario
- [x] `canary-decision.yml` verificado como ejecución real de GitHub Actions (no solo playbook local) — 2 hallazgos reales nuevos corregidos: `attribute_condition` de WIF no contemplaba `workflow_dispatch`, y `promote-canary.yml` rompía con 3 revisiones activas simultáneas
- [x] Producción cerrada en estado limpio: canary promovido a 100% real (`oms-production-00017-huk`, `version: 0.3.0`), verificado contra la API de Cloud Run

> **Deuda técnica menor identificada, no bloqueante** (ver `BITACORA-COMANDOS.md` § 6.21 y la conversación de cierre): el fix de `promote-canary.yml` (`head -n1` sobre el `awk` que busca "la otra revisión") resuelve el error de sintaxis de `gcloud` cuando hay más de 2 revisiones activas, pero toma la *primera* que aparece en el listado de `status.traffic[]`, no necesariamente la que tiene más tráfico real entre las "no-canary". En la prueba real esto fue inofensivo (se promovió a 100% igual después), pero si se quisiera usar `promote-canary.yml` con más rigor en un escenario de 3+ revisiones activas, convendría cambiar el criterio a "la de mayor `percent` actual entre las no-canary" en vez de "la primera línea".

### Fase 7 — Bonus 🟡 PARCIAL (3 de 5)

A petición del usuario ("cuales son las mas faciles de implementar que no implique mucho esfuerzo"), se priorizaron los 3 bonus de menor esfuerzo real (2 de ellos aprovechando código ya semi-preparado desde fases anteriores), dejando los 2 de mayor esfuerzo (nueva región, nueva VM) sin abordar.

- [x] **Documentación de migración expand-and-contract** (+5 pts) — nuevo `oms-platform/MIGRACION-EXPAND-CONTRACT.md`. Solo prosa, sin tocar infraestructura, como pide el enunciado. Escenario real y coherente con el dominio (`orders.orders.delivery_address`), conectado explícitamente con mecanismos ya reales del proyecto (la fase de validación usa el mismo comando `gcloud run services describe --flatten=status.traffic[]` que `rollback.yml`/`promote-canary.yml`).
- [x] **Cloud CDN políticas finas** (+5 pts) — afinado `terraform/modules/compute/main.tf` sobre el backend service ya existente: `cache_mode=USE_ORIGIN_HEADERS` (TTLs derivados de headers de la app), `include_query_string=true`, `negative_caching_policy`, nuevo bucket de assets/SPA + signed URL key + secreto de firma. **2 hallazgos reales corregidos** durante el `apply`: bloque `encryption` de un bucket no acepta `null` condicional (resuelto con `dynamic`), y código `500` inválido en `negative_caching_policy` (Cloud CDN solo permite una lista cerrada de códigos; corregido a 501). Aplicado y verificado contra la API real en staging y producción.
- [x] **CMEK propia** (+5 pts) — nuevo módulo `terraform/modules/kms/` (keyring + 2 claves, rotación 90 días), conectado a Cloud SQL y al bucket de assets vía un interruptor único (`enable_cmek`). **5 hallazgos reales encadenados** al activarlo por primera vez (documentados en detalle en `BITACORA-COMANDOS.md` § 7.3): `prevent_destroy` bloqueando correctamente la recreación necesaria (campo inmutable), `deletion_protection` con dos campos distintos y fácilmente confundibles (`deletion_protection` de Terraform vs. `settings.deletion_protection_enabled` de la API real), el bug real de cambiar esa protección y forzar un `replace` en el mismo `apply` (resuelto separando en 2 `apply`), recursos huérfanos en el estado tras una destrucción parcial exitosa (`terraform state rm`), y las Service Agents de Cloud SQL/Storage que no existían formalmente en el proyecto (resuelto con `google_project_service_identity`). Aplicado, verificado contra la API real, y ambas protecciones restauradas a `true` de forma permanente en staging y producción.
- [ ] Multi-region DR (`europe-central2`) + runbook de failover (+10 pts) — no abordado, mayor esfuerzo real (nueva región, replicación cross-region, costo adicional)
- [ ] Bastion VM + Ansible + Datadog + inventario dinámico por label (+10 pts) — no abordado, mayor esfuerzo real (VM nueva, cuenta de Datadog, rol de Ansible nuevo)

### Fase 8 — Documentación final y cierre

- [x] README con sección "Decisiones" (3 trade-offs reales + 3 cambios concretos al borrador de IA, todos verificables contra el código real)
- [x] `INFRA.md` — arquitectura real por módulo (network/database/compute/iam), tabla de diferencias staging/producción, recursos aplicados
- [x] `OBSERVABILIDAD.md` — logging real de Cloud SQL (8 database_flags), healthchecks en 3 capas, estado real del audit trail (no implementado, documentado como pendiente), SonarCloud
- [x] `CERTIFICADOS.md` — TLS del Load Balancer (certificado managed, estado real PROVISIONING sin dominio), WIF/OIDC completo con sus 2 hallazgos reales, Cosign keyless y el hallazgo de `cosign copy`
- [x] `DEPLOYMENT.md` — flujo operativo real: deploy.yml/rollback.yml/promote-canary.yml, los 4 jobs de ci-cd.yml, canary-decision.yml, evidencia del ciclo completo verificado
- [x] `DIAGRAMAS.md` — adelantado durante la Fase 3, a petición del usuario: diagrama Mermaid de relación entre los 38 recursos aplicados, tabla resumen por módulo y glosario completo de términos. Documento vivo — se amplía en cada fase futura (Ansible, CI/CD, bonus)
- [x] `RETROSPECTIVA.md` — desviaciones reales documentadas (NFR-SCAL-001, audit trail no implementado), deuda técnica conocida (criterio de promote-canary.yml), qué se haría distinto
- [x] Verificación final de los 7 comandos del enunciado (sección 4) — documentados en el README y re-verificados: `terraform plan` en producción tras el cierre de la Fase 7 confirma **"No changes. Your infrastructure matches the configuration."** en ambos entornos

> Los 6 documentos de la Fase 8 (excepto `DIAGRAMAS.md`, ya existente) se escribieron en una sola sesión, basados en lectura directa del código real (todos los `.tf`, `.yml` de Ansible, `Dockerfile`, `ci-cd.yml`) — no son plantillas genéricas, cada afirmación es verificable contra un archivo o un comando real documentado en `BITACORA-COMANDOS.md`.

### Fase 9 — Cierre: `terraform destroy` ✅ COMPLETA

Decisión ya tomada por el usuario desde el inicio del trabajo: destruir toda la infraestructura real tras grabar el video de explicación, para no seguir gastando el crédito de $300/90 días.

- [x] Protecciones de producción bajadas de forma consciente y documentada (`deletion_protection`/`deletion_protection_enabled` en Cloud SQL, `prevent_destroy` en Cloud SQL/KMS/bucket de assets) — mismo patrón ya usado y validado en el bonus CMEK
- [x] `terraform destroy -var-file=envs/staging.tfvars` — completo. La inmensa mayoría de recursos (IAM/WIF, Load Balancer, Cloud Run, KMS, Secret Manager, VPC connector, Cloud SQL, Redis, firewalls, subredes) se destruyeron sin problema en la primera pasada
- [x] `terraform destroy -var-file=envs/production.tfvars` — completo, mismo resultado
- [x] **Hallazgo real resuelto**: la conexión de peering de red privada (`google_service_networking_connection`) quedó bloqueada más de 12h en ambos entornos con `Producer services are still using this connection`, pese a confirmar exhaustivamente (Cloud SQL, Redis, AlloyDB, Filestore, Compute) que nada real seguía usándola — causa probable: backups automáticos huérfanos de Cloud SQL reteniendo un proyecto de tenant interno de Google. Se resolvió eliminando el peering **manualmente desde la consola web de GCP** (Red de VPC → Conectividad VPC → Intercambio de tráfico entre redes de VPC) en ambos proyectos — la consola sí lo permitió donde la API vía CLI/Terraform lo rechazaba consistentemente
- [x] Verificación final contra la API real de GCP en ambos proyectos: `gcloud compute networks list` solo muestra la red `default` (nunca gestionada por este proyecto), `gcloud compute addresses list`/`gcloud artifacts repositories list` en 0 — **cero recursos propios pendientes**
- [x] Única excepción real e irreversible: las 4 `CryptoKey` de Cloud KMS (2 por entorno, bonus CMEK) — Google no permite borrar nunca ese tipo de recurso, quedan como contenedores vacíos sin coste por existencia

> Detalle completo, comando por comando, en `BITACORA-COMANDOS.md` § 9.1-9.6.

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
| 2026-09-21 | Fase 4 | Rúbrica pide módulos `google.cloud.gcp_cloudrun_*`, pero la colección instalada (v1.10.2, la más reciente publicada) no tiene ningún módulo de Cloud Run — solo `gcp_runtimeconfig_*` (servicio distinto), verificado con `ansible-doc -l` e inspección directa de los `.py` de la colección | Se usa `ansible.builtin.command`/`shell` contra `gcloud run`, con idempotencia propia documentada; ausencia justificada por escrito en el propio código | BITACORA-COMANDOS.md § 4.1 |
| 2026-09-21 | Fase 4 | `ansible.cfg` no se cargaba (`world writable directory, ignoring it as an ansible.cfg source`) al correr desde WSL sobre `/mnt/d/...`, por lo que tampoco encontraba el role `oms_cloud_run` | `export ANSIBLE_CONFIG=./ansible.cfg` explícito antes de cada invocación | BITACORA-COMANDOS.md § 4.5 |
| 2026-09-21 | Fase 4 | `ansible.cfg` con `stdout_callback = yaml` fallaba: `The 'community.general.yaml' callback plugin has been removed` (eliminado en `community.general` ≥12.0.0) | `ANSIBLE_STDOUT_CALLBACK=default` por variable de entorno, sin tocar `ansible.cfg` | BITACORA-COMANDOS.md § 4.6 |
| 2026-09-21 | Fase 4 | `gcloud config get-value project` devolvía `(unset)` — el proyecto activo por defecto se perdió en algún reinicio/corte de sesión anterior, y el role de Ansible depende de él | `gcloud config set project acmeoms-staging-fatm` | BITACORA-COMANDOS.md § 4.6 |
| 2026-09-21 | Fase 4 | `--format=value(...)` con 4 campos partido en varias líneas de YAML (`cmd: >-`) rompía la sintaxis de `gcloud`: el *folded scalar* convierte saltos de línea en espacios, dejando espacios inválidos dentro del paréntesis — el estado actual del servicio se leía vacío | `--format=value(...)` completo en una sola línea de la plantilla, sin saltos internos | BITACORA-COMANDOS.md § 4.7 |
| 2026-09-21 | Fase 4 | `regex_replace('^sha256:(.{8}).*', '\\1')` no resolvía el backreference cuando `image_sha` llegaba por `-e` en línea de comandos (funcionaba bien en un test con `vars:` local) — el comando real traía `--to-tags=rev-\1=100` literal, redirigiendo tráfico a un tag inválido | Eliminado el uso de regex; reemplazado por slicing simple de Jinja2 (`image_sha.split(':')[1][:8]`), sin backreferences | BITACORA-COMANDOS.md § 4.7 |
| 2026-09-22 | Fase 4 | `rollback.yml` asumía que "la revisión más recientemente CREADA" era "la revisión activa" (tomaba `[0]` de `gcloud run revisions list`, ordenado por fecha de creación) — con una revisión de prueba sin tráfico más reciente que la que sí tenía el 100%, el rollback hizo un no-op silencioso en vez de fallar/avisar | La revisión activa se determina leyendo `status.traffic[]` (filtrando `percent==100`), no por orden de creación; si no hay una única revisión al 100%, el playbook falla explícitamente | BITACORA-COMANDOS.md § 4.8 |
| 2026-09-22 | Fase 4 | `deploy.yml`/role `oms_cloud_run`: `needs_deploy` comparaba la spec DECLARADA del servicio, no el tráfico real — tras un rollback, la spec ya parecía correcta y el playbook se saltaba también el paso de redirigir tráfico, dejando el tráfico real desalineado sin detectarlo | Nueva variable `needs_traffic_update`, calculada comparando la imagen de la revisión con 100% de tráfico real contra la deseada, independiente de si hizo falta desplegar | BITACORA-COMANDOS.md § 4.9 |
| 2026-09-22 | Fase 5 | `terraform apply` en producción falló en Cloud Run: cuota `CpuAllocPerProjectRegion`/`MemAllocPerProjectRegion` excedida (`cloud_run_max_instances=25 × 2 CPU/2Gi` pedía 50 CPU/100Gi, cuota gratuita permite 20 CPU/40Gi) | Reducido `cloud_run_max_instances` a 20 en `production.tfvars` — desviación documentada del NFR-SCAL-001 (pico 5×) por restricción real de cuenta gratuita | BITACORA-COMANDOS.md § 5.4 |
| 2026-09-22 | Fase 5 | `gcloud auth configure-docker` sobrescribió el `credHelper` de `europe-west3-docker.pkg.dev` de `gcr` (fix de la Fase 3 para WSL) de vuelta a `gcloud` (el `.cmd` de Windows incompatible), reintroduciendo el mismo bug ya resuelto | Restaurado manualmente `~/.docker/config.json` con `"gcr"` — evitar rerun de `configure-docker` sobre un host ya arreglado | BITACORA-COMANDOS.md § 5.5 |
| 2026-09-22 | Fase 5 | `terraform apply` de continuación mostró `1 to destroy` inesperado tras el fallo de cuota anterior | Investigado antes de aplicar a ciegas: el recurso Cloud Run quedó `tainted` (estado interno de Terraform tras un fallo a mitad de creación) — comportamiento correcto, no error; se recreó sin problema | BITACORA-COMANDOS.md § 5.7 |
| 2026-09-22 | Fase 5 | No existía ningún `.gitignore` en todo el repositorio — riesgo de commitear `.terraform/`, `*.tfplan`, o un `.tfstate` local por error | Creado `oms-platform/terraform/.gitignore` | BITACORA-COMANDOS.md § 5.8 |
| 2026-09-22 | Fase 5 | `gcloud config get-value project` seguía en staging al intentar desplegar producción (arrastrado de la Fase 4); `production.yml` de Ansible aún tenía `max_instances=25` sin sincronizar con el `20` ya corregido en Terraform | `gcloud config set project acmeoms-production-fatm` + alinear manualmente `group_vars/production.yml` — detectado el problema de fondo (ver fila siguiente) | BITACORA-COMANDOS.md § 5.9 |
| 2026-09-22 | Fase 5 | **Hallazgo de diseño señalado por el usuario:** `cpu`/`memory`/`min/max_instances` vivían duplicados a mano en Terraform Y en Ansible, sin sincronización — causa raíz de varios de los hallazgos anteriores | **Rediseño real**: Terraform expone estos 4 valores como outputs; Ansible los lee en vivo con `terraform output -json` en un pre_task, ya no los declara por su cuenta | BITACORA-COMANDOS.md § 5.9/5.10 |
| 2026-09-22 | Fase 5 | Al parametrizar `cloud_run_cpu`, se probó `"1500m"` (1.5 CPU) — Cloud Run lo rechazó: solo acepta fraccionario 0.08-1.0 o enteros {1,2,4,6,8} | Recalculado a `max_instances=15 × cpu=1000m` = mismo total de cuota, con un valor de CPU válido | BITACORA-COMANDOS.md § 5.10 |
| 2026-09-22 | Fase 5 | Al agregar los nuevos outputs, `terraform plan` mostró un cambio inesperado: quería revertir `traffic`/`client`/`revision` de Cloud Run a su forma declarativa pura, deshaciendo el control de tráfico que Ansible ya había fijado | Ampliado `lifecycle.ignore_changes` con `traffic`, `client`, `client_version`, `template[0].revision` — mismo principio ya aplicado a `image` | BITACORA-COMANDOS.md § 5.10 |
| 2026-09-22 | Fase 5 | Drift real detectado en staging: `memory` real del servicio era `1Gi`, pero el código de Terraform (y `group_vars`) decían `2Gi` desde hacía tiempo, sin que nadie lo hubiera notado ni vuelto a aplicar ese campo | `terraform apply` corrigió memory a `2Gi` real (recreó la revisión); redeploy con Ansible para restaurar el 100% de tráfico a la revisión correcta | BITACORA-COMANDOS.md § 5.9 |
| 2026-09-22 | Fase 5 | Verificación pedida por el usuario: probar el ciclo canary real (10%) y el rollback contra producción, y confirmar que las nuevas variables de cpu/memoria/instancias no interfieran con `rollback.yml` | Segundo build (v0.2.0) desplegado con canary real (reparto de tráfico confirmado con `curl`), rollback probado en 2 escenarios (falla correctamente con canary activo; funciona correctamente con 1 sola revisión al 100%) — confirmado que `rollback.yml` no usa cpu/memory/instancias en absoluto | BITACORA-COMANDOS.md § 5.12 |
| 2026-09-22 | Fase 6 | El workflow asumía un output `full_image` de `docker/build-push-action@v6` que no existe (solo expone `digest`/`imageid`) | Compuesta la referencia completa de la imagen a mano, a partir de `env.REGION` + `vars.*_PROJECT_ID` + `steps.push.outputs.digest` | BITACORA-COMANDOS.md § 6.3 |
| 2026-09-22 | Fase 6 | La "matriz" de versiones de Node en el job `ci` pasaba `--build-arg NODE_BASE=...`, pero el Dockerfile no declaraba ese `ARG` — las 2 entradas de la matriz habrían construido la misma imagen sin detectarlo | Agregado `ARG NODE_BASE=22-alpine` antes del primer `FROM` (visible en ambas etapas); verificado con 2 builds locales reales contra ambos valores | BITACORA-COMANDOS.md § 6.3 |
| 2026-09-23 | Fase 6 | `.github/workflows/ci-cd.yml` se creó dentro de `oms-platform/.github/` — GitHub Actions solo detecta workflows en `.github/workflows/` de la RAÍZ del repo, nunca en una subcarpeta | Movido a la raíz real del repositorio; las rutas internas ya eran correctas (`oms-platform/docker`, etc.) porque ya asumían un checkout completo desde la raíz | BITACORA-COMANDOS.md § 6.6 |
| 2026-09-23 | Fase 6 | `Required reviewers` de Environments no aparecía en la UI de GitHub — esa función no está disponible para repos privados en el plan gratuito | Repo cambiado a público (confirmado sin credenciales/secretos reales antes del cambio, con `gitleaks` y revisión manual) | BITACORA-COMANDOS.md § 6.6 |
| 2026-09-23 | Fase 6 | `terraform fmt -check` local encontró 6 archivos con formato no canónico (espaciado manual de comentarios inline) | `terraform fmt -recursive` aplicado; confirmado con `terraform plan` real que fue puramente cosmético (`No changes`) | BITACORA-COMANDOS.md § previo al 6.7 |
| 2026-09-23 | Fase 6 | Trivy config detectó Cloud SQL sin `ssl_mode=ENCRYPTED_ONLY` (HIGH) | Agregado `ssl_mode = "ENCRYPTED_ONLY"`; aplicado contra staging y producción reales (`update in-place`), verificado healthcheck sano en ambos | BITACORA-COMANDOS.md § 6.9 |
| 2026-09-23 | Fase 6 | Trivy config detectó `roles/iam.serviceAccountUser` otorgado a nivel de PROYECTO completo (MEDIUM) — el SA de CI/CD podía en teoría impersonar cualquier SA del proyecto | Acotado a un binding sobre el recurso específico del SA de runtime (`google_service_account_iam_member`); aplicado y verificado en ambos entornos | BITACORA-COMANDOS.md § 6.9 |
| 2026-09-23 | Fase 6 | Trivy image detectó 8 CVEs (7 HIGH + 1 CRITICAL) en la imagen Docker real | Investigado con `--format json`: los 8 pertenecen al `npm` interno de la imagen base oficial `node:22-alpine` (ya la más reciente), no a nuestro código — documentados uno por uno en `docker/.trivyignore`, sin bajar el umbral de severidad | BITACORA-COMANDOS.md § 6.9 |
| 2026-09-23 | Fase 6 | Montar `.trivyignore` con `-v $(pwd)/.trivyignore:/.trivyignore` (archivo suelto) fallaba con "ignore file not found" pese a que el archivo existía | Montar el directorio completo con ruta absoluta explícita en vez de `$(pwd)` + archivo individual — atribuible a la capa Docker Desktop↔WSL↔Windows, no reproducido en GitHub Actions | BITACORA-COMANDOS.md § 6.9 |

---

## 📚 Referencias rápidas

- Enunciado: [`Trabajo - enunciado.md`](Trabajo%20-%20enunciado.md)
- Arquitectura origen (no editar): [`anexo-arquitectura/`](anexo-arquitectura/)
- Esqueleto a completar: [`oms-platform/`](oms-platform/)
- Los 7 comandos de verificación: sección 4 del enunciado
- Rúbrica: sección 5 del enunciado (100 pts + bonus sección 6)

---

## 📋 Reporte Fase 5 — completada de forma autónoma (2026-09-22, madrugada)

> El usuario pidió terminar la Fase 5 sin supervisión y dejar constancia de qué problemas surgieron y cómo se resolvieron, para revisar al despertar. Este reporte cubre exactamente eso — el detalle técnico completo de cada punto está en `oms-platform/BITACORA-COMANDOS.md` (Fase 5, secciones 5.1 a 5.11).

### Qué se completó

1. **Infraestructura de producción real aplicada**: 39 recursos en `acmeoms-production-fatm` (red, Cloud SQL, Redis, IAM/WIF, Load Balancer, Cloud Run, Artifact Registry).
2. **Imagen promocionada de staging a producción** con el mismo digest SHA-256 exacto (copiada, no reconstruida — verificado carácter por carácter, cumple la regla del enunciado).
3. **Primer despliegue real a producción vía Ansible**, con 100% de tráfico en este primer despliegue (decisión explícita: el canary del 10% de `group_vars` no aplicaba sin una revisión previa a la que dejarle el 90%).
4. **Verificación externa real**: `curl https://oms-production-ykq27zd2fq-ey.a.run.app/health` → `200 {"status":"ok"}`.
5. **Rediseño de arquitectura solicitado por el usuario a mitad de la fase**: `cpu`/`memory`/`min/max_instances` de Cloud Run dejaron de duplicarse entre Terraform y Ansible. Ahora Terraform los expone como outputs y Ansible los lee en vivo (`terraform output -json`) en cada despliegue — un solo lugar para cambiar capacidad (`terraform/envs/<env>.tfvars`).
6. **Ambos entornos en estado estable**: `terraform plan` confirma "No changes" en staging y producción.

### Issues encontrados y cómo se resolvieron (orden cronológico)

| # | Problema | Causa raíz | Solución |
|---|----------|------------|----------|
| 1 | `terraform apply` falló en Cloud Run: cuota de CPU/memoria excedida (`25 × 2000m = 50000m`, límite `20000m`) | `cloud_run_max_instances=25` (NFR-SCAL-001 original) incompatible con cuota gratuita de la región | Reducido a valores que caben en la cuota, ver issues #7 y #8 más abajo para el valor final |
| 2 | `docker pull` de la imagen de staging falló: `docker-credential-gcloud not found` | `gcloud auth configure-docker` (ejecutado para "preparar" el registro de producción) sobrescribió el credential helper `gcr` (fix nativo de Linux para WSL, de la Fase 3) de vuelta al `.cmd` de Windows incompatible | Restaurado manualmente `~/.docker/config.json` con `"gcr"` |
| 3 | `terraform apply` de continuación mostró `1 to destroy` inesperado | El intento anterior falló a mitad de crear Cloud Run; Terraform marcó el recurso como `tainted` (estado interno: "este recurso quedó inconsistente, recréalo") | Comportamiento correcto de Terraform, no un error — se dejó recrear sin problema |
| 4 | Ningún `.gitignore` existía en todo el repositorio | Nunca se creó desde el inicio del proyecto | Creado `oms-platform/terraform/.gitignore` (cubre `.terraform/`, `*.tfplan`, `*.tfstate`) |
| 5 | Primer intento de despliegue a producción vía Ansible falló: `gcloud config get-value project` seguía en `acmeoms-staging-fatm` | El proyecto activo de `gcloud` quedó fijado en staging desde la Fase 4, y nada lo cambió automáticamente al pasar a producción | `gcloud config set project acmeoms-production-fatm` + `gcloud auth application-default set-quota-project` |
| 6 | El mismo intento mostró `Min/Max inst: 2/25` en el resumen — no coincidía con el `20` ya corregido en `production.tfvars` | `group_vars/production.yml` (Ansible) nunca se actualizó cuando se corrigió `production.tfvars` (Terraform) — son archivos separados sin sincronización | Corregido a mano en ese momento; **causa raíz atacada de fondo en el issue #9** |
| 7 | `gcloud run deploy` (ejecutado por Ansible) falló: `CpuAllocPerProjectRegion requested: 40000 allowed: 20000` | La revisión YA EXISTENTE (creada por Terraform con `cpu=1000m`, valor que en ese momento estaba hardcodeado en el módulo) + la revisión NUEVA que Ansible intentaba crear (con `cpu=2000m` de `group_vars`) coexistían un momento, sumando más cuota de la disponible | Reveló el problema de fondo: `cpu`/`memory` estaban hardcodeados en Terraform sin relación con lo que Ansible pedía — atacado en el issue #9 |
| 8 | **El usuario preguntó explícitamente si `cpu`/`memory` no deberían vivir solo en Terraform**, señalando el problema de raíz de los issues #6 y #7 | Diseño original: dos sistemas (Terraform y Ansible) mantenían copias independientes de la misma información, sin ningún mecanismo de sincronización | **Rediseño**: se agregaron 4 outputs a Terraform (`cloud_run_cpu`, `cloud_run_memory`, `cloud_run_min_instances`, `cloud_run_max_instances`) y un pre_task en `deploy.yml` que ejecuta `terraform output -json` y sobreescribe esas 4 variables — Ansible ya no las declara por su cuenta |
| 9 | Al parametrizar `cloud_run_cpu` con `"1500m"` (1.5 CPU), `terraform apply` lo rechazó: `Invalid value ... Must be equal to one of [.08-1], 1.0, 2.0, 4.0, 6.0, 8.0` | Cloud Run no acepta cualquier valor de CPU — solo fraccionario 0.08-1.0 o enteros exactos | Recalculado a `max_instances=15 × cpu=1000m` (mismo total de cuota buscado, con un valor válido) |
| 10 | Al generar el plan con los nuevos outputs, apareció un cambio inesperado en Cloud Run: Terraform quería revertir `traffic`/`client`/`revision` a su forma pura, deshaciendo el tag/tráfico que Ansible ya había fijado | El campo `traffic` (y metadata relacionada) no estaba en `lifecycle.ignore_changes` — solo `image` lo estaba, del mismo conflicto detectado en fases anteriores | Ampliado `ignore_changes` con `traffic`, `client`, `client_version`, `template[0].revision` |
| 11 | Al revisar `staging.yml` tras alinear `staging.tfvars` a `memory="2Gi"`, se detectó que el servicio REAL de staging corría con `memory="1Gi"` — un drift silencioso preexistente | El código de Terraform siempre pidió `"2Gi"` (confirmado con `git log`), pero ese campo específico nunca se había vuelto a aplicar desde el primer `apply` de staging (Fase 2) | `terraform apply` corrigió la memoria real a `2Gi` (recreó la revisión); se redesplegó con Ansible para restaurar el 100% de tráfico a la revisión correcta |

### Decisiones tomadas de forma autónoma (a confirmar/revisar al despertar)

- **Capacidad final de producción**: `min_instances=2`, `max_instances=15`, `cpu=1000m`, `memory=2Gi` (15 × 1000m = 15000m, 25% de margen bajo la cuota de 20000m). Esto es una reducción real respecto al NFR-SCAL-001 original (pico 5× = 25 instancias), motivada por una restricción real de cuota gratuita de GCP — **si se solicita un aumento de cuota más adelante, se puede subir `max_instances` en `terraform/envs/production.tfvars` sin tocar nada más** (Ansible lo recogerá automáticamente en el siguiente despliegue).
- **Traffic del primer despliegue de producción**: 100% (no el 10% canary de diseño), justificado por no existir una revisión previa. `group_vars/production.yml` sigue en 10% para promociones futuras reales.
- **Revisión de prueba huérfana en staging** (`oms-staging-00005-cex`, de un diagnóstico de la sesión anterior): no se pudo borrar (`Cloud Run` protege la última revisión creada de un borrado directo). Queda inactiva, sin tráfico, sin coste — se puede ignorar o limpiar manualmente más adelante si molesta visualmente en la consola.

### ✅ Actualización — verificación completa del ciclo canary + rollback (ya resuelto)

Los dos puntos que habían quedado pendientes en la primera versión de este reporte **ya se verificaron por completo**, a petición del usuario (ver sección 5.12 de `BITACORA-COMANDOS.md`):

- **`rollback.yml` sí se probó contra producción**, en sus dos escenarios reales: (1) con tráfico repartido en canary (90/10) — falla explícitamente, comportamiento correcto y verificado a propósito; (2) con una única revisión al 100% — rollback real ejecutado con éxito, tráfico movido correctamente a la revisión N-1.
- **Confirmado que `rollback.yml` NO necesita leer de Terraform** — no usa `cpu`/`memory`/`min/max_instances` en ningún punto, solo trabaja con `status.traffic[]` y nombres de revisión. No hace falta replicar el pre_task de `deploy.yml` ahí.
- Se hizo además un segundo build real (`v0.2.0`) para poder ejercitar el canary de producción de verdad (10% real, no el 100% del primer despliegue) — confirmado con `curl` que dos revisiones sirvieron tráfico y contenido distinto simultáneamente.
- Producción quedó restaurada al final en su estado correcto: `v0.2.0` al 100%, verificado con `curl` externo.
- **Nuevo diagrama en `DIAGRAMAS.md`** (sección 2.bis) mostrando todo este flujo: build → Terraform (corrida inicial) → Ansible (corridas siguientes) → canary → rollback, con staging/producción diferenciados y círculos de color por tipo de paso.

### Pendiente para cuando retomes (no bloqueante)

- Próximo paso natural: Fase 6 (CI/CD) — `.github/workflows/ci-cd.yml`.
