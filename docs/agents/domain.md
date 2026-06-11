# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Layout

This repo uses a single-context layout:

```
/
├── CONTEXT.md
├── docs/adr/
└── docs/agents/
```

`CONTEXT.md` and `docs/adr/` may not exist yet. If they are absent, proceed silently; do not flag their absence or create them preemptively. The producer skill (`/grill-with-docs`) creates them lazily when terms or architectural decisions are resolved.

## Before exploring, read these

- `CONTEXT.md` at the repo root, if present.
- `docs/adr/`, if present; read ADRs that touch the area you are about to work in.
- Existing project guidance in `CLAUDE.md` and operational docs such as `README.md`, `docs/WSUS-Manager-SOP.md`, and `wiki/Developer-Guide.md` when relevant to the task.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, refactor proposal, hypothesis, or test name), use the term as defined in `CONTEXT.md` when that file exists. Do not drift to synonyms the glossary explicitly avoids.

If the concept you need is not in the glossary yet, either reconsider whether you are inventing language the project does not use, or note the gap for `/grill-with-docs`.

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding it:

> Contradicts ADR-0007 — but worth reopening because...
