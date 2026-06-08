# Política de error budget — Equipo OMS

> Una página. Niveles numéricos. Consecuencias explícitas. Sin ambigüedad.

---

## SLO sobre el que aplica esta política

TODO referencia al SLO al que aplica la política.
> Ej: "Disponibilidad de `POST /orders` — 99,5% no-5xx en ventana 28d rolling."

**Error budget total:** TODO minutos al mes (calculado en `slos-orders.md`).

---

## Niveles y consecuencias

### 🟢 Verde — > 50% del budget restante

**Ritmo:** normal.
**Despliegues:** sin restricción.
**Sprint:** trabajo de features sin limitación.

### 🟡 Amarillo — entre 10% y 50% del budget restante

**Trigger:** se detecta al cruzar el 50% restante o tras un incidente que consumió > 20%.
**Ritmo:** monitoreado.
**Despliegues:** permitidos pero **toda PR de feature nueva requiere análisis de impacto en disponibilidad** firmado por el revisor.
**Sprint:** se revisa el ratio features / fiabilidad cada lunes en el standup.

### 🔴 Rojo — < 10% del budget restante

**Trigger:** se cruza el 10% restante.
**Ritmo:** estabilización.
**Despliegues:** **freeze de features**. Solo se mergea código que reduzca riesgo (fix, retry, mejor manejo de errores).
**Sprint:** > 50% de la capacidad del equipo se reasigna a reducir incidentes recurrentes y reforzar runbooks.
**Comunicación:** se avisa a producto en el sync semanal con cifras del budget.

### ⚫ Agotado — 0% del budget

**Ritmo:** post-mortem obligatorio del periodo.
**Decisión escalada:** la VP de Ingeniería decide si:
- Relajar el SLO (ej: pasar de 99,5% a 99,0%) si el negocio puede asumirlo.
- Reasignar capacidad de otros equipos para acelerar estabilización.
- Mantener el SLO y aceptar que durante X tiempo el equipo no entregará features.

---

## Excepciones

**PRs etiquetadas como `safety-fix`** se pueden mergear en cualquier estado del budget. Requieren approval del on-call de la semana.

---

## Revisión

Esta política se revisa **cada trimestre** con producto. Si los supuestos del usuario han cambiado (más tráfico, más exigencia, expansión a nuevos países con expectativas distintas), se ajusta el SLO antes que la política.

---

## TODO(alumno)
- [ ] Calcula tu error budget exacto (en minutos al mes) y rellénalo arriba
- [ ] Decide si activas la regla de "amarillo si tras un incidente se consume > 20%" o usas otro umbral. Justifica.
- [ ] Añade un párrafo sobre quién es el "on-call" en tu organización ficticia y cómo se contacta
