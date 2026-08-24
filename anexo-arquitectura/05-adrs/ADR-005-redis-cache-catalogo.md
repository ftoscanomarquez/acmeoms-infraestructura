# ADR-005 · Redis como caché read-through del catálogo

## Estado
**Aceptada** · 2025-01-15

## Contexto

Tras decidir [PostgreSQL único multi-AZ](ADR-004-postgresql-multi-az.md), se observa que el módulo `catalog` tiene un perfil distinto al resto:

- Es **el módulo más leído** del sistema (el cliente navega antes de comprar).
- El **catálogo cambia poco** — entre 10 y 50 actualizaciones al día (asunción A-003).
- **NFR-PERF-001** exige `GET /api/products` con **p95 < 150ms bajo 800 req/s**.
- **NFR-AVAIL-002** exige catálogo 99.95% — más exigente que checkout (99.9%).

Mediciones de baseline (medidas en staging con dataset realista de 50K productos):

| Endpoint | p95 sin caché | NFR objetivo | Gap |
|----------|---------------|--------------|-----|
| `GET /api/products` (listing 20 items) | 220ms | 150ms | -70ms |
| `GET /api/products/:id` | 80ms | 150ms | ✓ cumple |
| `GET /api/categories` | 35ms | 150ms | ✓ cumple |

El listing falla NFR-PERF-001 con la BD optimizada (índices ya existentes en `catalog.products(category_id)` y `catalog.products(active, featured)`). Más optimización SQL no rasca los 70ms restantes; necesitamos otra capa.

> 💡 **NOTA · V2 — De NFR a decisión arquitectónica**
> Un NFR cuantificado con un gap demostrado es lo que justifica una nueva pieza de infraestructura. Sin gap, añadir Redis es overengineering.

## Decisión

Introducir **Redis como caché read-through delante de PostgreSQL para el módulo catalog únicamente**, con las siguientes características:

### 1 · Patrón

**Read-through con invalidación explícita por evento:**

```
Cliente
  │ GET /api/products?category=X
  ▼
catalog.HttpController
  │
  ▼
catalog.ListProductsUseCase
  │
  ├──► ProductCache (port)  ← Redis adapter
  │      ├─ HIT  → devolver datos cacheados
  │      └─ MISS → consultar PostgreSQL, guardar en Redis con TTL
  │
  └──► ProductRepository (port)  ← solo en MISS
```

### 2 · Política de TTL

| Tipo de dato | TTL | Justificación |
|--------------|-----|---------------|
| Listings (paginados, por categoría) | 5 min | Cambio típico baja frecuencia; staleness aceptable |
| Producto individual | 30 segundos | Más agresivo porque la página de producto es más sensible a precios |
| Categorías (árbol completo) | 30 min | Cambian muy raramente |

### 3 · Invalidación explícita

Además del TTL, ciertos eventos invalidan claves específicas:

| Evento | Invalidación |
|--------|--------------|
| `ProductUpdated(productId)` | Invalida `product:{productId}` + listings de la categoría |
| `ProductCreated(productId)` | Invalida listings de la categoría |
| `ProductDeactivated(productId)` | Invalida `product:{productId}` + listings |
| `PriceChanged(productId, ...)` | Invalida `product:{productId}` + listings |

La invalidación se dispara desde el módulo `catalog` mismo cuando publica los eventos (no es comunicación cross-módulo).

### 4 · Solo en `catalog`

**Esta caché NO se aplica a otros módulos.** Las razones por bounded context:

- `inventory`: stock cambia constantemente, caché contraproducente.
- `orders`, `payments`, `billing`: lecturas individuales por ID, ya rápidas con índice.
- `iam`: datos sensibles, prefiere consultar fuente de verdad.

### 5 · Topología

- **Primary + replica en eu-west-1** (alta disponibilidad).
- Tipo: **AWS ElastiCache for Redis** o equivalente.
- Tamaño: **cache.t4g.medium** (~50 €/mes, suficiente para ~5GB de datos cacheados).

### 6 · Estrategia ante fallo del cache

**Graceful degradation:** si Redis no está disponible, el adapter devuelve "miss" y la lectura va a PostgreSQL directamente. Logs de WARN se emiten pero no se rompe el sistema.

```typescript
class RedisProductCache implements ProductCache {
  async get(key: string): Promise<Product | null> {
    try {
      return await this.redis.get(key);
    } catch (e) {
      logger.warn({ event: 'cache_miss_due_to_error', error: e.message });
      return null; // tratamiento como miss
    }
  }
}
```

## Consecuencias

### Positivas

- **NFR-PERF-001 cumple con margen** — medido en producción tras implementar: p95 = 35ms (objetivo 150ms).
- **Reduce carga sobre PostgreSQL** ~85% en el primary (medido con `pg_stat_statements`).
- **NFR-AVAIL-002 mejora** — el catálogo puede servirse desde caché incluso cuando la BD está en mantenimiento programado breve.
- **Coste razonable** — ~50 €/mes encajan en presupuesto OPS-003.
- **Aislado al módulo catalog** — el resto del sistema no se ve afectado por decisiones específicas del cacheado.
- **Operación familiar** — Redis es estándar industrial, Equipo SRE ya lo opera.

### Negativas

- **Consistencia eventual** entre Redis y PostgreSQL durante la ventana de TTL — un cliente puede ver el precio antiguo durante hasta 5 min después de un cambio. Mitigación: invalidación explícita por evento reduce la ventana real a segundos en la mayoría de casos.
- **Riesgo de cache stampede** — si una clave caliente expira con miles de requests concurrentes, todos golpean la BD a la vez. Mitigación: implementar single-flight pattern (solo un request va a la BD; el resto espera).
- **Nuevo servicio que mantener** — backups, parches, monitorización (memoria, hit ratio, evictions).
- **Dependencia adicional** que puede caerse — graceful degradation diseñada explícitamente.
- **Posibles bugs de invalidación** — un evento que no invalida la clave correcta = clientes ven datos viejos hasta el TTL. Mitigación: tests de integración que verifican que cada evento dispara la invalidación esperada.

## Alternativas descartadas

### A · Read replicas de PostgreSQL

**Por qué se descartó:**
- Latencia medida con réplica de lectura: p95 ~180ms. Sigue por encima del objetivo 150ms.
- La latencia adicional viene del round-trip y serialización SQL, no del bloqueo del primary.
- Ofrece menos margen que Redis.
- Coste similar a la opción elegida pero con peor resultado.

### B · CDN para JSON del catálogo (CloudFront con caching agresivo)

**Por qué se descartó:**
- La invalidación en CDN es lenta (minutos en propagar) — incompatible con cambios frecuentes de precios o stock.
- Requeriría marcar URLs como cacheables, lo cual rompe con headers personalizados (auth, locale).
- Sí lo usaremos para imágenes y la SPA estática (ver [ADR-008](ADR-008-frontend-spa-cdn.md)), pero no para JSON de producto.

### C · Materialized views en PostgreSQL

**Por qué se descartó:**
- Latencia medida: p95 ~110ms. Más cerca del objetivo pero sin margen.
- La actualización de la vista materializada bloquea reads o requiere `REFRESH CONCURRENTLY` que sigue golpeando el primary.
- Añade complejidad sin un beneficio claro sobre Redis para este caso.

### D · Caché en proceso (in-memory) en cada réplica del monolito

**Por qué se descartó:**
- Inconsistente entre réplicas: dos pods sirven datos distintos del mismo producto.
- Complica mucho la invalidación (hay que propagar a todas las réplicas).
- No cumple un sistema multi-réplica con autoescalado donde los pods aparecen y desaparecen.

### E · Memcached en lugar de Redis

**Por qué se descartó:**
- Funcionalidades de Redis (TTL fino por clave, pub/sub para invalidación, persistencia opcional) son útiles aquí.
- Equipo conoce mejor Redis. Sin razón fuerte para cambiar.

## Re-evaluación

Esta decisión se debe revisar cuando:

- La **tasa de invalidaciones por minuto** crezca > 100 — síntoma de que el catálogo cambia más de lo asumido (A-003) y el TTL aporta poco valor frente al coste.
- **Hit ratio < 70%** sostenido — la caché no está aportando lo esperado; revisar tamaño, claves y patrones de acceso.
- **NFR-PERF-001 se vuelva más exigente** (< 50ms) — habría que considerar caché en CDN para listados públicos.
- **Aparezca otro módulo con perfil de lectura intensiva** — extender el patrón requeriría considerar una caché compartida o por módulo.

## Referencias

- ADR previos: [ADR-001](ADR-001-monolito-modular.md), [ADR-004](ADR-004-postgresql-multi-az.md)
- Asunción que valida: A-003 (catálogo cambia ≤ 50/día)
- Restricción cumplida: NFR-PERF-001

---

> 💡 **NOTA PEDAGÓGICA — Vídeo 1, Vídeo 2**
>
> Este ADR ilustra dos lecciones clave:
>
> 1. **Las decisiones arquitectónicas se justifican con números.** El gap entre 220ms (lo que da PostgreSQL) y 150ms (lo que pide el NFR) es lo que motiva una nueva pieza. Sin ese gap, añadir Redis sería overengineering.
>
> 2. **Las consecuencias negativas se documentan honestamente.** La consistencia eventual entre Redis y PostgreSQL es una contrapartida real. Documentarla evita la sorpresa cuando aparezca el primer reporte de "vi un precio viejo".
>
> Fíjate también en cómo el ADR cita las alternativas con datos concretos (réplicas dan 180ms, vistas materializadas 110ms). En proyectos reales, hay que medir antes de elegir.
