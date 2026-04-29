# Guía de Specs — daniel15k-api

Este documento define el estándar para todos los archivos en `specs/`. Aplica a specs nuevos y a la edición de specs existentes.

---

## Convenciones generales

**Nombres de archivo:** kebab-case siempre. `planned-expenses.md`, no `planned_expenses.md`.

**Idioma:** español en títulos, metadata y prosa. El código (Ruby, JSON, SQL) va en el idioma que corresponda.

**Un spec = una responsabilidad.** Si un archivo necesita cubrir dos dominios distintos, es señal de que debe dividirse.

---

## Header obligatorio

Todo spec comienza con el mismo bloque:

```markdown
# <Título Descriptivo>

> Estado: <emoji> <texto>
> Última actualización: YYYY-MM-DD
> Depende de: <spec1.md>, <spec2.md>   ← omitir si no aplica
```

### Estados disponibles

| Emoji | Significado |
|-------|-------------|
| ✅ | Completo / vigente / implementado |
| 🟡 | En progreso / parcial |
| 🔲 | Pendiente / futuro — no iniciar aún |
| ⚠️ | Parcialmente supersedido — verificar código |

El campo `Depende de` lista solo los specs que **deben leerse antes** de implementar este.

---

## Plantilla 1 — Dominio técnico

Para dominios de infraestructura: `auth`, `authorization`, `forms`, `oauth`, etc.

```markdown
# Dominio <Nombre> — <Responsabilidad breve>

> Estado: ✅ completo
> Última actualización: YYYY-MM-DD
> Depende de: architecture.md

## Propósito

Una o dos oraciones. Qué problema resuelve este dominio.

## Qué hace / Qué NO hace

### Hace
- ...

### No hace
- ...

## Modelo de datos

Migraciones, relaciones, campos relevantes.

## Implementación

Entities → Value Objects → Repository → Interactor → Presenter → Controller.
Solo incluir lo no-obvio o lo que difiere del flujo estándar.

## Endpoints

Tabla: método · ruta · permiso requerido · descripción.

## Definición de done

Lista de checkboxes verificables.
```

---

## Plantilla 2 — Feature del módulo

Para funcionalidades de negocio dentro de `specs/finanzas/`.

```markdown
# <Nombre de la feature>

> Estado: 🟡 en progreso
> Última actualización: YYYY-MM-DD
> Spec relacionado: <otro-spec.md>   ← omitir si no aplica

## Qué resuelve

El problema concreto que motiva esta feature. Sin esta sección el spec no tiene contexto.

## Modelo de datos

Tablas nuevas o campos nuevos. Solo lo necesario para entender el contrato.

## Contrato de API

Endpoints, parámetros, respuestas. Usar bloques de código HTTP.

## Invariantes

Reglas de negocio que el backend debe respetar siempre, sin excepción.
Estas son las reglas que el agente y el frontend no pueden violar.

## Definición de done

Lista de checkboxes verificables.
```

---

## Qué NO va en un spec

- Código de implementación completo (factories, specs RSpec, seeds completos). Eso vive en el código.
- Decisiones ya tomadas y reflejadas en el código — no documentar lo que se puede leer en el repo.
- TODOs o notas personales. El tracker de fases es `finanzas/fases.md`.
- Referencias a archivos externos fuera del repo (links a BRAND.md del proyecto web, etc.).

---

## Archivo de tracker

`specs/finanzas/fases.md` es el único archivo de estado del módulo Finanzas. No duplicar estado en los specs individuales más allá del campo `Estado:` del header.
