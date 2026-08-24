# ADR-006 · Stripe como PSP con tokenización delegada

## Estado
**Aceptada** · 2025-01-15

## Contexto

El módulo `payments` debe procesar cobros con tarjeta cumpliendo:

- **REG-PCI-001** — datos de tarjeta nunca en logs ni en BD propia
- **REG-PCI-002** — patrones de PAN no aparecen en logs
- **NFR-SEC-003** — tokenización delegada al PSP (no almacenamos PAN, CVV, expiry)
- **NFR-SEC-002** — TLS 1.3 entre cliente y PSP
- **REG-GDPR-001** — datos de pago de ciudadanos UE deben procesarse en regiones UE

Adicionalmente:

- El equipo es pequeño (OPS-001) — convertirse en entidad PCI-DSS Level 1 requeriría un compliance officer dedicado y auditoría anual ~25-50K €/año.
- Se prioriza **time-to-market**: queremos lanzar pagos en semanas, no meses.
- El volumen previsto (2.000 pedidos/día normal, 10.000 en pico) es perfectamente manejable por un PSP estándar.

> 💡 **NOTA · V1 — Restricciones inflexibles**
> Las regulatorias no se negocian: el sistema TIENE que cumplir PCI-DSS o no procesa pagos con tarjeta. La pregunta no es "si cumplimos", sino "cómo cumplimos con el menor esfuerzo posible".

## Decisión

Usar **Stripe** como PSP con **tokenización delegada (Stripe.js + Payment Intents API)**:

### 1 · Flujo de tokenización

```
1. Cliente accede a checkout
2. Frontend carga Stripe.js (servido desde stripe.com, no por nuestro backend)
3. Cliente introduce datos de tarjeta en un IFrame de Stripe (NO pasan por nuestro backend)
4. Stripe.js devuelve un token (paymentMethodToken) al frontend
5. Frontend envía orderId + paymentMethodToken a nuestro backend
6. Backend llama a Stripe API: paymentIntent.confirm(amount, paymentMethodToken)
7. Stripe procesa, devuelve transactionId + status
8. Backend almacena transactionId (no PAN) en payments.payment_intents
```

**Lo que nunca toca nuestro backend:** PAN, CVV, fecha de expiración.
**Lo que sí almacenamos:** `paymentIntentId` (referencia opaca de Stripe), `last4` (últimos 4 dígitos para mostrar al cliente, permitido por PCI), `cardBrand`.

### 2 · Alcance PCI reducido — SAQ-A

Al usar tokenización con IFrame de Stripe (sin que los datos de tarjeta toquen nuestro frontend o backend), nuestro alcance PCI se reduce a **SAQ-A** (Self-Assessment Questionnaire A): cumplimiento autocertificado, sin auditoría obligatoria.

### 3 · Anti-Corruption Layer (ACL)

El módulo `payments` define puertos en el dominio con tipos del dominio:

```typescript
// payments/domain/ports/driven/PaymentGateway.ts
export interface PaymentGateway {
  authorize(input: AuthorizeInput): Promise<AuthorizationResult>;
  capture(authorizationId: string): Promise<CaptureResult>;
  refund(input: RefundInput): Promise<RefundResult>;
}

export type AuthorizationResult = {
  success: boolean;
  paymentIntentId?: string;
  errorCode?: 'INSUFFICIENT_FUNDS' | 'CARD_DECLINED' | 'NETWORK_ERROR' | 'FRAUD_SUSPECTED';
};
```

La implementación `StripePaymentGateway` traduce el modelo de Stripe al modelo del dominio:

```typescript
// payments/adapters/payment/StripePaymentGateway.ts
class StripePaymentGateway implements PaymentGateway {
  async authorize(input: AuthorizeInput): Promise<AuthorizationResult> {
    try {
      const intent = await this.stripe.paymentIntents.create({
        amount: input.amount.cents(),
        currency: input.amount.currency().toLowerCase(),
        payment_method: input.paymentMethodToken,
        confirm: true,
        capture_method: 'manual', // captura diferida
      });
      return { success: true, paymentIntentId: intent.id };
    } catch (e) {
      return { success: false, errorCode: this.mapStripeError(e) };
    }
  }

  private mapStripeError(e: Stripe.errors.StripeError): AuthorizationResult['errorCode'] {
    if (e.code === 'card_declined') return 'CARD_DECLINED';
    if (e.code === 'insufficient_funds') return 'INSUFFICIENT_FUNDS';
    if (e.type === 'StripeCardError') return 'CARD_DECLINED';
    return 'NETWORK_ERROR';
  }
}
```

### 4 · Webhooks

Stripe notifica eventos asíncronos (capture confirmada, dispute abierto, refund completado) vía webhooks HTTPS. El módulo `payments` expone `POST /webhooks/stripe` con verificación de firma (`stripe.webhooks.constructEvent`). Estos webhooks generan eventos de dominio (`PaymentCaptured`, `PaymentDisputed`, `PaymentRefunded`) que circulan por el event bus interno.

### 5 · Sanitización de logs

Para cumplir REG-PCI-002, todos los logs estructurados pasan por un middleware que **redacta cualquier patrón que parezca PAN** (Luhn-valid sequence de 13-19 dígitos):

```typescript
function sanitizeLog(payload: object): object {
  const json = JSON.stringify(payload);
  const sanitized = json.replace(/\b(?:\d[ -]*?){13,19}\b/g, '[REDACTED-PAN]');
  return JSON.parse(sanitized);
}
```

Tests unitarios verifican que números de tarjeta de prueba no aparezcan jamás en los logs.

## Consecuencias

### Positivas

- **REG-PCI-001 cumplido** sin convertirnos en entidad PCI Level 1.
- **REG-PCI-002 cumplido** con sanitización + tokenización (los logs no pueden contener PAN porque el PAN nunca entra al backend).
- **NFR-SEC-003 cumplido** trivialmente — Stripe es la fuente de verdad de datos de tarjeta.
- **Time-to-market rápido** — Stripe.js + Payment Intents son APIs maduras, integración en días.
- **El dominio aislado de Stripe** — si mañana Stripe sube precios o cierra servicio en UE, escribimos `AdyenPaymentGateway` sin tocar `Orders`.
- **Reducción del riesgo legal** — el alcance PCI-SAQ-A es manejable; PCI-DSS Level 1 sería un proyecto en sí mismo.

### Negativas

- **Dependencia de un proveedor externo** — si Stripe cae, no procesamos pagos. Mitigación: monitorización del SLA de Stripe (publicado), comunicación clara al cliente cuando hay incidente externo.
- **Coste por transacción** — Stripe cobra ~1.4% + 0.25 € por transacción europea. A 2.000 pedidos/día con ticket medio 50 €, ~600 €/mes en fees. Aceptable comparado con coste de PCI-DSS Level 1.
- **Acoplamiento al modelo de errores de Stripe** — el ACL traduce, pero hay que mantener el mapeo cuando Stripe añade códigos nuevos.
- **Webhooks pueden llegar duplicados o desordenados** — gestionar idempotencia en `payments` (ver patrón en ADR-009).
- **Reembolsos diferidos** — si el cliente solicita refund, va al PSP y volvemos vía webhook; la UI debe reflejar "en proceso".
- **Datos de tarjeta no portables** — si migramos a otro PSP, los métodos de pago guardados (cards on file) no se transfieren automáticamente. Mitigación: la mayoría de PSPs tienen "data portability programs" para migración.

## Alternativas descartadas

### A · Construir nuestro propio sistema de pagos PCI-DSS Level 1

**Por qué se descartó:**
- Coste estimado: > 200K € primer año (auditoría, infraestructura, compliance officer, tests).
- 6-12 meses de delay en time-to-market.
- Equipo de 8 developers no puede absorber compliance PCI sin sacrificar features.
- Solo justificable si procesamos > 6M transacciones/año (Level 1) y queremos negociar fees agresivos. No es nuestro caso.

### B · Adyen como PSP

**Por qué se descartó:**
- Equivalente en cumplimiento y modelo (tokenización delegada).
- Stripe elegido por:
  1. **Familiaridad del equipo** (V2: cuando opciones son equivalentes, gana lo familiar).
  2. **Documentación más completa** y comunidad más grande.
  3. **API más estable** y deprecaciones bien gestionadas.
- Adyen es la alternativa de respaldo si Stripe se vuelve inviable: la abstracción del puerto `PaymentGateway` permite la migración.

### C · Redsys (PSP español, dominante en España)

**Por qué se descartó:**
- API legacy (basada en formularios HTML y firmas SHA-256) — peor DX.
- Tokenización menos integrada — tendríamos que diseñar más infraestructura.
- Fees competitivos pero diferencia no compensa la complejidad de integración para nuestro volumen.
- Considerar como fallback regional si los costes de Stripe se vuelven prohibitivos.

### D · Pasarela self-hosted (Hyperswitch, Spreedly, etc.)

**Por qué se descartó:**
- Vuelve a ponernos como entidad relevante PCI (alcance no se reduce solo por usar software open source).
- Coste operativo no compensa: tendríamos que mantener un sistema crítico extra con su propio equipo SRE.

### E · Pago contra reembolso / transferencia bancaria como único método

**Por qué se descartó:**
- Tasa de conversión muy inferior a tarjeta en e-commerce B2C español.
- Restricción de negocio: el cliente espera pagar con tarjeta.

## Re-evaluación

Esta decisión se debe revisar cuando:

- El **coste de fees Stripe supere ~3% del ticket medio** sostenido — evaluar negociación o multi-PSP routing.
- Aparezca un **PSP local con mejores fees y certificación SAQ-A** competitiva.
- Stripe **deje de cumplir A-001** (asunción: SAQ-A en regiones UE durante el horizonte).
- Aparezca **e-invoicing obligatorio en España B2C** (asunción A-004) que requiera integración profunda con la fiscalía y replanteamiento del flujo.

## Referencias

- ADR previos: [ADR-002](ADR-002-hexagonal-por-modulo.md) (el ACL es hexagonal puro)
- Restricciones cumplidas: REG-PCI-001, REG-PCI-002, NFR-SEC-003, NFR-SEC-002

---

> 💡 **NOTA PEDAGÓGICA — Vídeos 1 y 5**
>
> Este ADR ilustra dos lecciones:
>
> 1. **Restricciones regulatorias decididas en abstracto** se traducen en decisiones técnicas muy concretas (V1). PCI-DSS no dice "usa Stripe", pero la consecuencia económica de cumplirlo en casa empuja hacia un PSP.
>
> 2. **Hexagonal protege la inversión** (V5). El día que Stripe falle, suba precios o cambie API de forma incompatible, lo único que cambia es `StripePaymentGateway.ts`. El módulo `Orders` no se entera. Esa es la razón concreta por la que pagamos el coste de los puertos.
>
> Pregunta de examen: ¿qué cambia en el código si mañana migramos a Adyen? Respuesta correcta: un archivo (el adapter), más quizás algunos códigos de error en el mapping. NO cambia el dominio, NO cambian los use cases, NO cambian los controllers HTTP.
