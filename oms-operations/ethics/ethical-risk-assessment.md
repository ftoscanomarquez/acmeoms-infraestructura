# Ethical Risk Assessment — Asistente IA de soporte al cliente del OMS

> **OPCIONAL (bonus +10 pts).** Asume que añadimos al OMS un asistente
> con IA que ayuda al cliente con dudas sobre su pedido en chat.
> Si te tomas en serio el cierre del Vídeo 5, esto es lo que tienes
> que producir antes de que ese asistente entre en producción.

---

## Sistema bajo evaluación

**Nombre:** OMS Customer Support Assistant
**Descripción:** chatbot LLM que responde al cliente preguntas sobre:
- Estado de su pedido (en preparación, enviado, entregado)
- Reembolsos y cambios
- Información del catálogo
- Escalada a un agente humano cuando detecta frustración

**Modelo:** TODO. Ej: Claude Sonnet 4.6 vía API.
**Datos a los que accede:** TODO. Ej: pedidos del usuario autenticado, catálogo público, FAQ interna.
**Quién toma la decisión final:** el chatbot da respuesta inmediata, el cliente puede pedir agente humano en cualquier momento.

**Clasificación EU AI Act:** TODO. Pista: probablemente "riesgo limitado" (informa, no decide sobre derechos del cliente). Justifica.

---

## Evaluación de riesgos

| # | Riesgo | Sev (1-5) | Prob (1-5) | Control técnico | Control organizativo | Responsable | Evidencia para auditoría |
|---|---|---|---|---|---|---|---|
| 1 | TODO Sesgo demográfico | TODO | TODO | TODO | TODO | TODO | TODO |
| 2 | TODO Alucinación sobre estado de pedido (responde "está enviado" cuando no lo está) | TODO | TODO | TODO | TODO | TODO | TODO |
| 3 | TODO Filtración de datos personales (responde sobre el pedido de otro cliente) | TODO | TODO | TODO | TODO | TODO | TODO |
| 4 | TODO Prompt injection | TODO | TODO | TODO | TODO | TODO | TODO |
| 5 | TODO Coste descontrolado (loop de turnos) | TODO | TODO | TODO | TODO | TODO | TODO |

---

## Quality attributes derivados (van a la spec del sistema)

Cada riesgo identificado se traduce en al menos un requisito verificable de la spec:

1. **TODO** ej: "Trazabilidad por turno: cada respuesta del asistente queda registrada con trace_id y aceptación del cliente. `audit_log_completeness >= 99,9%`."
2. **TODO** ej: "Verificación de pertenencia: antes de exponer datos de pedido, el sistema verifica `pedido.user_id == sesion.user_id`. Tests de no-regresión en CI."
3. **TODO** ej: "Presupuesto de tokens por sesión: máximo `MAX_TOKENS_PER_SESSION = 50.000`. Si se supera, escalado a humano."
4. **TODO** ej: "Sandboxing del prompt: el system prompt no puede ser sobreescrito por input del usuario. Tests adversariales en CI."
5. **TODO** ej: "Rate limiting: máximo N mensajes/cliente/hora. Alerta si una sesión genera > X tokens."

---

## Cómo se monitoriza en producción

TODO conexión con tu instrumentación.
- Métricas: `assistant_tokens_per_session`, `assistant_human_escalation_rate`, `assistant_response_accepted_rate`
- Alertas: TODO ej: si la tasa de escalada a humano > 30%, hay un problema sistémico, no individual
- Runbook: TODO crear `runbooks/0X-assistant-degraded`

---

## Revisión y gobierno

- **Frecuencia de revisión:** trimestral, conjunta entre Ingeniería, Legal y Atención al Cliente.
- **Decisión de retirada:** si se materializa un riesgo de severidad 5 sin control efectivo, el asistente se desactiva vía feature flag (el de V4) hasta resolver.
- **Owner del documento:** TODO.

---

## Cierre

TODO una frase tuya sobre lo que has aprendido haciendo este ejercicio.
> Ej: "Antes de este trabajo pensaba que la ética en IA era un seminario; ahora veo que es una columna de la tabla de riesgos, con número, owner y evidencia."
