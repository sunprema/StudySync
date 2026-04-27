# ARCHITECTURE.md — StudySync

This document is a stub. Architecture rules and rationale live in the project's operating manual; this file exists as a stable entry point for orientation.

## Where to read next

- **Operating manual & architectural rules** — [`CLAUDE.md`](./CLAUDE.md)
- **Product requirements** — [`references/REQUIREMENTS.md`](./references/REQUIREMENTS.md)
- **Build roadmap (vertical slices)** — [`references/ROADMAP.md`](./references/ROADMAP.md)

## Stack at a glance

- Elixir + Phoenix LiveView (page composition, navigation, forms)
- Ash Framework + AshPostgres (resources, actions, policies)
- One Svelte 5 component (`PdfCanvasRenderer`) for PDF.js rendering — see CLAUDE.md §4.2
- PostgreSQL · Oban (background jobs, `default` and `:ai` queues) · Phoenix PubSub (real-time)
- Tailwind CSS v4 + DaisyUI v5 (single `studysync` theme — Margin Notes palette)

## The contract

The LiveView ↔ Svelte boundary is the only API surface between the two worlds. Its props and events are enumerated in CLAUDE.md §4.3 and **must be updated in the same PR** as any code change that adds to it.
