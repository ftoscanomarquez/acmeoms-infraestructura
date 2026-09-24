# CERTIFICADOS.md — TLS, identidad federada y firma de imágenes

Este proyecto no usa Traefik ni mkcert (el material del bloque cubre esos escenarios para entornos donde tú gestionas el proxy). Aquí el TLS del tráfico de usuarios lo gestiona por completo el **Load Balancer de GCP**, y la identidad para CI/CD y la firma de imágenes usan **OIDC federado**, no certificados propios ni claves estáticas. Este documento cubre los tres mecanismos reales: TLS del LB, Workload Identity Federation, y Cosign.

## 1 · TLS del tráfico de usuarios — certificado managed de Google

`terraform/modules/compute/main.tf` declara un `google_compute_managed_ssl_certificate`: Google emite y renueva el certificado automáticamente, sin gestión manual ni Let's Encrypt propio. Requisito real para que llegue a estado `ACTIVE`: el dominio indicado (`var.lb_domain`) necesita un registro DNS tipo A apuntando a la IP pública del Load Balancer (`google_compute_global_address.lb_ip`).

**Estado real de este proyecto**: no existe un dominio real registrado (comprarlo es un recurso externo que no cubre el crédito de GCP ni es parte del alcance de infraestructura del enunciado). Se usa un placeholder explícito (`pendiente-dominio-real.example.com`, en minúsculas — ver nota de diseño abajo). El certificado se crea igual pero queda permanentemente en `PROVISIONING`, sin bloquear el resto del despliegue — Cloud Run sigue siendo accesible por su propia URL nativa (`cloud_run_url`, output de Terraform) con HTTPS ya válido mientras tanto (certificado gestionado automáticamente por el propio Cloud Run, independiente del Load Balancer).

**Por qué el dominio placeholder está en minúsculas**: GCP normaliza el campo `domains` de un certificado managed a minúsculas al crearlo. Si se declara con mayúsculas en Terraform, `plan` detecta una diferencia permanente entre "lo que se pidió" y "lo que GCP realmente guardó" — y como ese campo es inmutable, cada `apply` posterior fuerza destruir y recrear el certificado. Comprobado en la práctica durante la Fase 2.

TLS 1.3 (NFR-SEC-002): el Load Balancer `EXTERNAL_MANAGED` de GCP soporta TLS 1.3 por defecto en su política SSL — no requiere configuración explícita adicional para este alcance.

## 2 · Workload Identity Federation (WIF) — identidad para CI/CD sin claves estáticas

Cero credenciales estáticas en todo el pipeline (rúbrica, 10 pts + penalización de -20 si aparece una). GitHub Actions obtiene un token OIDC efímero de GitHub, y GCP lo intercambia por credenciales temporales del Service Account de CI/CD — sin ningún JSON de Service Account en `secrets`.

### Cómo está configurado (`terraform/modules/iam/main.tf`)

Un pool + provider WIF por entorno:

```hcl
resource "google_iam_workload_identity_pool_provider" "github" {
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
    "attribute.event_name" = "assertion.event_name"
  }
  attribute_condition = <<-EOT
    assertion.repository == "${var.github_repository}" &&
    (
      assertion.ref.startsWith("refs/tags/v") ||
      (assertion.event_name == "workflow_dispatch" && assertion.ref == "refs/heads/main")
    )
  EOT
}
```

**La seguridad real vive en `attribute_condition`, no en el YAML del workflow.** Aunque alguien modificara `.github/workflows/ci-cd.yml` para intentar desplegar desde una rama cualquiera, GCP rechazaría la autenticación de todas formas — el trust policy en GCP es la barrera de verdad, el workflow es solo la orquestación.

### Dos hallazgos reales de diseño de esta condición

**1. El `audience` por defecto no es el que un ejemplo genérico podría sugerir.** Una nota inicial del proyecto asumía `allowed_audiences = ["sts.amazonaws.com"]` como valor estándar (posiblemente heredado de un ejemplo de AWS/STS). En la práctica, `google-github-actions/auth@v2` genera el token OIDC con *audience* = la URL completa del propio proveedor WIF (`https://iam.googleapis.com/projects/.../providers/github-provider`), no ese valor. Con `allowed_audiences` fijado así, la autenticación real fallaba con:
```
invalid_grant: The audience in ID Token [...] does not match the expected audience.
```
Se eliminó el campo por completo — al omitirlo, GCP usa su propio default (la URL del provider), que es exactamente lo que la acción oficial ya genera.

**2. La condición inicial no contemplaba un segundo flujo legítimo de producción.** Al agregar `canary-decision.yml` (disparado por `workflow_dispatch` sobre `main`, no por un tag), la condición original —que solo aceptaba `assertion.ref.startsWith("refs/tags/v")`— rechazaba el token real:
```
unauthorized_client: The given credential is rejected by the attribute condition.
```
Correcta en su momento (pensada solo para `ci-cd.yml`), pero incompleta. Se amplió agregando `attribute.event_name` al mapping y el segundo caso del `||` — aceptando explícitamente *solo* `workflow_dispatch` sobre `refs/heads/main`, nunca cualquier rama o fork. Aplicado con `terraform apply` real y verificado contra la API de GCP (`iam.googleapis.com`) leyendo el recurso directamente, no solo confiando en el resumen del `apply`.

### Impersonación del Service Account

```hcl
resource "google_service_account_iam_binding" "cicd_wif" {
  role = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${pool.name}/attribute.repository/${var.github_repository}",
  ]
}
```

Solo identidades cuyo `attribute.repository` coincida exactamente con el repo configurado pueden impersonar el SA de CI/CD — el mismo repo real, no un fork.

## 3 · Firma de imágenes — Cosign keyless

"El workflow construye, prueba, firma y despliega" (árbol de entregables del enunciado). La firma usa **Cosign en modo keyless**: sin `--key`, sin clave privada persistida en ningún sitio.

### Cómo funciona en la práctica

1. En el job `build` (`.github/workflows/ci-cd.yml`), tras construir y subir la imagen a Artifact Registry de staging:
   ```bash
   cosign sign --yes "${REGION}-docker.pkg.dev/${STAGING_PROJECT}/oms/oms@${DIGEST}"
   ```
   Cosign reutiliza el **mismo token OIDC** de GitHub Actions (el de `permissions: id-token: write`, esta vez dirigido a Sigstore/Fulcio, no a GCP) para pedir un certificado de un minuto de validez, y firma con él. La firma queda adjunta al digest en el propio registro, más un registro público e inmutable en el *transparency log* de Rekor.

2. En `deploy-staging` y `deploy-production`, antes de desplegar:
   ```bash
   cosign verify \
     --certificate-identity-regexp="^https://github.com/<owner>/<repo>/.github/workflows/ci-cd.yml@.*$" \
     --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
     "<imagen>@<digest>"
   ```
   Cierra el ciclo: no basta con firmar, hay que **exigir** una firma válida antes de desplegar. Si alguien empujara una imagen distinta al mismo tag sin pasar por este pipeline exacto, no tendría una firma válida de esta identidad concreta y el despliegue se detiene ahí.

### Hallazgo real: la firma no viaja con un `docker tag`+`push`

Al promocionar la imagen a producción (`deploy-production`), la firma de Cosign es un **artefacto OCI adjunto al registro donde se creó** (staging) — no algo que un simple `docker tag`+`push` copie junto con la imagen a otro registro. Sin corrección, `cosign verify` contra producción fallaba con `Error: no signatures found`, aunque el digest fuera exactamente el mismo y sí tuviera una firma válida en staging.

Corrección: `cosign copy --only=sig` copia solo la firma (la imagen ya se copió por separado con `docker`), preservando el certificado y timestamp **originales** de cuando se firmó en el job `build` — nunca se vuelve a firmar en producción, se propaga la firma original:

```bash
cosign copy --only=sig \
  "<imagen>@<digest>"@staging \
  "<imagen>@<digest>"@producción
```

Esta operación necesita leer del registro de staging y escribir en el de producción en la misma llamada, pero el pipeline solo mantiene una identidad GCP activa a la vez. Se resolvió con un permiso cross-proyecto explícito: el SA de CI/CD de producción tiene `roles/artifactregistry.reader` sobre el proyecto de staging (`terraform/modules/iam/main.tf`, condicionado a que `staging_project_id` esté definido — solo aplica en `production.tfvars`).

### Por qué esto cumple la regla de "mismo `image_sha` en ambos entornos"

Como la promoción es literalmente copiar el mismo digest (nunca reconstruir), y la firma que se propaga es la firma original de ese mismo build, es estructuralmente imposible que producción termine ejecutando un binario distinto al que ya se validó en staging — la penalización de -10 pts del enunciado por SHAs distintos no puede ocurrir con este diseño salvo que alguien edite el workflow a mano para saltarse el paso de `docker pull` del digest de staging.
