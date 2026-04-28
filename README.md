# StudySync

A collaborative, AI-assisted study platform centered on PDF-based learning. A reading group uploads a book, reads it together asynchronously, anchors discussion to specific passages via annotations, and tracks progress through milestones and rubber stamps.

The core loop: **Read → Highlight → Annotate → Discuss → AI → Save → Progress.**

## Design direction

StudySync ships **Direction 01 — Margin Notes**: a classical book-margin metaphor. Annotations live in a literal margin column to the right of the page, anchored via footnote-style numbered markers (¹, ², ³) inline in the prose. Warm, literary, paper-cream surface with terracotta as the lone accent.

Two themes are available: `study_sync_default` (Margin Notes, default) and `nord` (opt-in alternate). Users switch from the avatar dropdown.

## Domain model

- **Workspace** — top-level tenant with members (`:admin`, `:member`).
- **Resource** — an uploaded PDF belonging to a workspace.
- **Annotation** — first-class object anchored to `(resource, page_number, rect)`. Has a type (`:comment | :question | :puzzle | :ai_response`), color, visibility, captured text snippet, and user.
- **AnnotationComment** — a reply within an annotation's thread. AI replies set `is_ai_response: true`.
- **MilestoneMarker** — admin-placed checkpoint anchored to `(resource, page, position)`.
- **RubberStamp** — a user's completion mark against a milestone.

## Stack

- **Backend / UI** — Elixir + Phoenix LiveView
- **Resource layer** — Ash Framework (system of record for resources, actions, and policies)
- **Interactive UI** — Svelte 5 via Live Svelte (only the PDF canvas)
- **Database** — PostgreSQL
- **Background jobs** — Oban
- **Real-time** — Phoenix PubSub + LiveView
- **Styling** — Tailwind CSS v4 + DaisyUI v5
- **PDF rendering** — PDF.js inside the Svelte canvas component

## Architecture

- LiveView owns page composition, navigation, forms, lists, and panels.
- A single Svelte component (`PdfCanvasRenderer`) owns PDF rendering, text selection, highlight overlays, annotation markers, and milestone markers.
- The LiveView ↔ Svelte contract is narrow and documented in `CLAUDE.md` §4.3 — extend it deliberately, not on a whim.
- Real-time updates broadcast over Phoenix PubSub on `"resource:#{resource_id}"` topics.
- AI assistant calls and any work >150ms run as Oban jobs.

## Getting started

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Then visit [`localhost:4000`](http://localhost:4000) from your browser.

## Project documentation

- `CLAUDE.md` — operating manual for coding agents working in this repo (architecture rules, visual system, conventions).
- `references/REQUIREMENTS.md` — full product spec.
- `references/ROADMAP.md` — slice-by-slice build plan; check items off as they ship.
- `.claude/skills/frontend/references/StudySync_Design Explorations.pdf` — visual reference (pages 2–5 are Direction 01).

## Build priority

1. PDF Viewer + Text Selection
2. Annotation Creation + Display
3. Bi-directional Sync (PDF ↔ margin panel)
4. Annotation Threads
5. AI Integration
6. Milestone + Rubber Stamp System

## Deployment

Ready to run in production? See the [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Phoenix: https://www.phoenixframework.org/ · [guides](https://hexdocs.pm/phoenix/overview.html) · [docs](https://hexdocs.pm/phoenix)
* Ash Framework: https://ash-hq.org · [docs](https://hexdocs.pm/ash)
* Live Svelte: https://hexdocs.pm/live_svelte
