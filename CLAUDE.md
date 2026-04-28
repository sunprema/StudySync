# CLAUDE.md — StudySync (Direction 01: Margin Notes)

This file is the operating manual for any Claude coding agent working on this codebase. Read it first. Re-read it whenever the user asks for a feature that touches a system you haven't worked in yet.

---

## 1. What you are building

**StudySync** is a collaborative, AI-assisted study platform centered on PDF-based learning. A reading group uploads a book, reads it together asynchronously, anchors discussion to specific passages via annotations, and tracks progress through milestones and rubber stamps.

We are building **Direction 01 — Margin Notes**: a classical book-margin metaphor. Annotations live in a literal margin column to the right of the page, anchored via footnote-style numbered markers (¹, ², ³) inline in the prose. Warm, literary, paper-cream surface with terracotta as the lone accent.

The full product spec lives in `references/REQUIREMENTS.md`. The visual reference lives in `.claude/skills/frontend/references/StudySync_Design Explorations.pdf` (pages 2–5 are Direction 01). When the spec and this file disagree, **ask the user before deviating** — don't pick a side silently.

## The product roadmap is in `references/ROADMAP.md` . When you work on the slices, make sure, you checkmark the items as completed.

## 2. Stack

- **Backend / UI** — Elixir + Phoenix LiveView
- **Resource layer** — Ash Framework (Ash is the system of record for resources, actions, and policies; do not write Ecto schemas directly for domain resources)
- **Interactive UI** — Svelte 5 via Live Svelte (only for high-frequency DOM work — see §6)
- **Database** — PostgreSQL
- **Background jobs** — Oban
- **Real-time** — Phoenix PubSub + LiveView
- **Styling** — Tailwind CSS v4 + DaisyUI v5
- **PDF rendering** — PDF.js (inside the Svelte canvas component)

The user has strong Elixir/Ash/Phoenix depth. Match that — use idiomatic Ash patterns (resources, actions, policies, calculations, aggregates) rather than reaching for raw Ecto unless there's a reason Ash can't express the thing.

---

## 3. Domain model — the words that matter

Use these names exactly. Don't synonym-drift them ("note" instead of "annotation", "stamp" instead of "rubber_stamp", "highlight" instead of "annotation of type comment", etc.).

- **Workspace** — top-level tenant. Has members with roles (`:admin`, `:member`).
- **Resource** — an uploaded PDF belonging to a workspace.
- **Annotation** — a first-class object anchored to a `(resource, page_number, rect)`. Has a `type` (`:comment | :question | :puzzle | :ai_response`), a `color`, a `visibility` (`:private | :workspace`), a captured `text` snippet, and a `user_id`.
- **AnnotationComment** — a reply within an annotation's thread. Has `is_ai_response` boolean.
- **MilestoneMarker** — admin-placed checkpoint anchored to `(resource, page, position)`.
- **RubberStamp** — a user's completion mark against a milestone. Optional note.

The core loop is: **Read → Highlight → Annotate → Discuss → AI → Save → Progress.** Every feature should be evaluated against whether it strengthens or weakens that loop.

---

## 4. Architectural rules

### 4.1 Ash is the resource layer

- Domain entities are Ash resources. Actions go through Ash actions, not direct Repo calls.
- Authorization is expressed as Ash policies, not scattered through controllers/LiveViews.
- Use `AshPostgres` for persistence. Use Ash calculations/aggregates for derived data (e.g. "completion %", "stamp count per milestone").
- Use `AshDoubleEntry` only if/when we add anything ledger-shaped — not relevant for MVP.
- **Carve-out: `Studysync.Chat`** (Slice 18) is intentionally not an Ash resource because it has no persistence — chat messages live in an ETS ring buffer for the lifetime of the BEAM node and are gone after a restart. Authorization is enforced in plain Elixir via `Workspaces.actor_member?/2`. Any other "no DB, just memory" side-channel can follow the same pattern; everything else still goes through Ash.

### 4.2 LiveView owns the page, Svelte owns the canvas

- Page composition, navigation, forms, lists, panels → **LiveView + Phoenix components**.
- The PDF canvas (PDF.js rendering, text selection, highlight overlays, annotation markers, milestone markers) → **one Svelte component**, `PdfCanvasRenderer`.
- Anything else in Svelte requires explicit justification. Default answer is no.

### 4.3 The LiveView ↔ Svelte contract is narrow

This is the only API surface between the two worlds. Keep it small and stable.

**Props (LiveView → Svelte):**

- `file_url` — auth-gated URL the canvas fetches the PDF from (added Slice 3)
- `total_pages` — page count from the persisted resource, used for the indicator before PDF.js finishes loading (added Slice 3)
- `annotations[]`
- `milestone_markers[]` — `[{ id, page, position: { x, y }, label }]`, position normalized 0..1 to the page (added Slice 12)
- `is_admin?` — boolean; true when the actor is an admin of the resource's workspace. Surfaces the "+ Place milestone" option in the floating selection menu. (added Slice 12; replaced the earlier `milestone_mode` prop when placement moved into the selection menu.)
- `rubber_stamps[]` — `[{ id, milestone_id, user_id, email }]` — every stamp visible to the actor on this resource. The canvas uses it to render the per-milestone "X / N readers" popover and to know whether the current user has already stamped. (added Slice 13)
- `current_user_id` — UUID of the signed-in actor. The canvas compares against `rubber_stamps[].user_id` to decide whether to show the stamp button or a "Stamped" indicator on the milestone popover. (added Slice 13)
- `total_readers` — workspace active-member count, used as the denominator in the "X / N readers" label on the milestone popover. (added Slice 13)
- `active_annotation_id`

**Events (Svelte → LiveView):**

- `text_selected` → `{ text, page, rect, type }` — `type` ∈ `"comment" | "question" | "puzzle" | "milestone"`. The `"milestone"` variant is admin-only and only emitted when the canvas's `is_admin?` prop is true (Slice 12 revised); the LV opens a label form in the margin pre-filled with the selected text, and `save_milestone` creates the milestone using the rect's top-left for `position`. (added Slice 10; `"milestone"` added when the placement UX moved into the selection menu.)
- `annotation_clicked` → `{ id }`
<!-- `milestone_placed` was retired in Slice 12 (revised, take 2): milestone
placement now flows through `text_selected` with `type: "milestone"`, so
there's no dedicated event. The earlier "click anywhere to drop" mode and
the `milestone_mode` prop are gone with it. -->

- `apply_stamp` → `{ milestone_id }` — fired when the user confirms a stamp from the per-milestone popover. The LiveView authorises through Ash, applies the stamp, and broadcasts (`:stamp_applied`) so all open readers re-fetch and patch. (added Slice 13)
- `pages_visible` → `{ first, last, primary }` — debounced (~120ms) report of the page range currently intersecting the viewport. `first`/`last` come from the canvas's IntersectionObserver (with its 1000px rootMargin) and define the virtualization range. `primary` is the page with the largest *true* viewport overlap — the LiveView uses it as the focal page so the margin column's focal-page highlight and the "Page" scope tab match what the reader is actually looking at, not whatever sliver of an adjacent page sits within the rootMargin buffer. (added Slice 15; lazy-hydration role removed in Slice 15a — the reader now eagerly loads the whole book at mount. `primary` added when the margin scope tabs landed.)
- `outline_loaded` → `{ chapters: [{ label, page }] }` — fired once after PDF.js loads the document, with the top-level outline entries flattened to `{ label, page }` pairs (page is 1-indexed). Empty list when the PDF has no outline. The LiveView stores it as `@chapters` and feeds the chapter rail. Top-level only — nested outline items are ignored to keep the rail visually quiet. (added Slice 17)
- `chapter_clicked` → `{ page }` — fired by the chapter rail (LV-rendered, `phx-click`) when a reader clicks a chapter. The LiveView validates `page` is in range and pushes `scroll_to_page` back to the canvas. (added Slice 17)

**Server-pushed events (LiveView → Svelte):**

These are emitted via `push_event/3` and consumed inside the Svelte canvas via `useLiveEvent` from `live_svelte`. Use sparingly — prefer prop changes when the UI depends on persistent state. Server-pushed events are for one-shot, ephemeral signals where adding a prop just to bump a nonce would be noise.

- `scroll_to_page` → `{ page }` — fires when the LiveView wants the canvas to bring a specific page into view (currently used by the chapter rail). The canvas calls `scrollIntoView({ behavior: "smooth", block: "start" })` on the matching slot. The canvas's `pages_visible` IO callback then updates `:focal_page` naturally — no separate state sync needed. (added Slice 17; an earlier `scroll_to_page` from the first cut of Slice 15a was removed before 15a closed; this is its re-introduction for chapter navigation.)

If you need a new prop or event, **add it to this contract in the same PR** and update §4.3 here. Don't smuggle in undocumented channels.

### 4.4 Real-time is Phoenix PubSub

Topics are scoped per resource: `"resource:#{resource_id}"`. Broadcast new annotations, new comments, and new stamps. LiveViews subscribe on mount and patch their assigns on receive. No server-pushed events to Svelte directly — go LiveView → assign → prop.

### 4.5 Background work is Oban

- AI assistant calls (`Ask AI`) are dispatched as Oban jobs. The job writes back an `AnnotationComment` with `is_ai_response: true` and broadcasts via PubSub. The LiveView reflects it like any other comment.
- Anything that could take >150ms or hit an external API goes through Oban. Don't block the LiveView process.

---

## ELIXIR DEPS

- Elixir libs are added as deps in mix.exs
- The libaries are added to /deps/<library_name> folder.
- You can check the documentation of library under /deps/<library_name>/README.md file.
- If you have any question about using a library, you should check the README.md of the library first, then the code inside for deeper look.

## 5. Direction 01 visual system (Margin Notes)

This is non-negotiable for any UI work. If a design choice isn't covered here, match the reference PDF.

### 5.1 Palette

| Token          | Value     | Use                                            |
| -------------- | --------- | ---------------------------------------------- |
| `--paper`      | `#F4EFE3` | Primary background                             |
| `--paper-2`    | `#E8E0CE` | Margin column, secondary surfaces              |
| `--terracotta` | `#B8512E` | Sole accent — markers, active state, key links |
| `--ink`        | `#2A2521` | Primary text                                   |
| `--ink-soft`   | `#5C5750` | Secondary text, labels                         |

Highlight tints on selected text are low-saturation pastels (peach, mint, lavender, butter). Avatars use a small, fixed palette of muted brand tints — never random.

### 5.2 Typography

- **Display / serif** — Instrument Serif. Used for book titles, screen titles ("Recent", "Quiet hours", "Notes"), and large numerals.
- **Body** — a quiet humanist serif for prose inside the PDF text rendering and annotation bodies (Source Serif or similar).
- **UI / labels** — JetBrains Mono (or similar geometric mono), uppercase, tracked, for metadata: `MARGIN · 3 NOTES`, `HERE NOW · 4`, page numbers, timestamps.
- **Tabular numerals** — use a `.num` utility for any column of numbers (progress %, time spent, page numbers in lists).

### 5.3 Layout primitives

- **Reader screen** — three columns: thin chapter rail (left, ~40px, vertical mono labels) · page surface (center, generous whitespace) · margin column (right, `--paper-2` background, ~360px). Footnote markers in the prose are small terracotta superscripts; they correspond 1:1 to numbered cards in the margin.
- **Library screen** — book title in Instrument Serif (xl), a horizontal progress timeline with avatar dots pinned to position, a grid of reader cards below, and a right rail with live activity.
- **Study room** — left rail (presence + timer in Instrument Serif numerals) · center synced page surface · right panel of shared sticky notes on a tinted board.

### 5.4 The aesthetic

Quiet, literary, warm. Generous whitespace. No drop shadows on flat surfaces. No gradients except subtle tints. No emoji in UI. The product should feel like reading in a good library, not like a SaaS dashboard.

The user has explicitly rejected dark/industrial aesthetics for this product. Don't drift toward it.

**Themes.** The app ships two themes — `study_sync_default` (the warm Margin Notes palette, default) and `nord` (an opt-in alternate). The active theme is persisted on `Studysync.Accounts.User.theme` and applied via `data-theme` on `<html>`; users switch themes from the avatar dropdown rendered by `<StudysyncWeb.Layouts.user_menu>`. Nord is implemented in `assets/css/app.css` as a `[data-theme="nord"]` block that overrides the raw palette tokens (`--color-paper`, `--color-ink`, `--color-terracotta`, etc.) — every existing `bg-paper` / `text-ink` / `text-terracotta` utility flips automatically. Highlight tints (peach/mint/lavender/butter) intentionally do **not** flip — they encode annotation type, not theme. New themes follow the same pattern: register a DaisyUI block, override the palette tokens, and add the key to the User attribute's regex constraint. Don't add themes that contradict the literary/warm direction above (e.g. synthwave, cyberpunk) — Nord is the carve-out, not a precedent for industrial styles.

### 5.5 Phoenix components

Build these as `~H` function components in `lib/study_sync_web/components/`:

- `<.margin_note>` — single annotation card in the margin
- `<.footnote_marker>` — inline superscript marker
- `<.chapter_rail>` — vertical chapter index
- `<.reader_card>` — member card on the library screen
- `<.activity_item>` — single row in the activity rail
- `<.sticky_note>` — note on the study room board

Co-locate styles via Tailwind utilities. Use DaisyUI semantic classes (`btn`, `card`) sparingly and override the theme to match the palette in §5.1.

---

## 6. Performance contract

These are real requirements, not aspirations. Reading is the product — latency degrades it visibly.

- **Annotations are lazy-loaded per page.** Don't ship the whole book's annotations on mount.
- **LiveView re-renders are scoped.** Use `phx-update="stream"` for annotation lists and activity feeds. Don't re-render the PDF canvas on every PubSub message.
- **PDF rendering uses page virtualization.** Only render pages near the viewport.
- **Perceived interaction latency is <100ms.** Optimistic UI for annotation creation: show the new card in the margin immediately, reconcile on server ack.
- **Highlight overlays are drawn in Svelte, not in LiveView.** LiveView pushes the data; Svelte paints.

---

## 7. Coding conventions

### 7.1 Elixir

- `mix format` is law. Run before every commit.
- Modules follow Phoenix/Ash conventions: `StudySync.Library.Resource`, `StudySync.Annotations.Annotation`, etc. Group resources into Ash domains by bounded context.
- Public functions get `@doc` and `@spec`. Private helpers don't need either unless they're tricky.
- Pattern match in function heads. Prefer `with` over nested `case` for happy-path-with-failures.
- LiveView assigns are flat and named clearly. No `assigns.data.thing.nested.deeply`.

### 7.2 Naming

- Resource files use snake_case singular: `annotation.ex`, not `Annotations.ex`.
- LiveView modules end in `Live`: `PdfLive.Show`, `AnnotationPanelLive`.
- Phoenix components are snake_case function names: `<.margin_note>`.
- DB tables are plural snake_case: `annotations`, `annotation_comments`, `rubber_stamps`.

### 7.3 Tests

- Every Ash action has a test in the corresponding `_test.exs`.
- LiveView interactions are tested with `Phoenix.LiveViewTest`. At minimum: mount, primary interaction, PubSub broadcast reception.
- Don't test framework code (don't test that Ash inserts a row). Test our logic.

### 7.4 Migrations

- Generated via Ash (`mix ash.codegen`). Don't hand-write migrations for resource changes.
- One migration per logical change. Don't bundle unrelated changes.

---

## 8. How to work in this repo

### 8.1 Before writing code

1. Read the relevant section of `REQUIREMENTS.md`.
2. Skim this file's relevant section.
3. If the change is non-trivial (new resource, new screen, new contract event), write a short plan first and confirm with the user.

### 8.2 Scope discipline

- Do what was asked. Don't refactor adjacent code, don't rename things, don't "clean up" unrelated files.
- If you find a real problem outside scope, mention it at the end of your response — don't fix it inline.
- If a request is ambiguous, ask one specific question rather than guessing across multiple axes.

### 8.3 What's out of scope (MVP)

Per `REQUIREMENTS.md` §9: no mobile-first UI, no audio/video annotations, no offline support, no LMS integrations. Don't add these without an explicit ask.

Also out of scope until explicitly requested: flashcard generation, public marketplace, gamification, educator analytics.

### 8.4 Common traps

- **Don't put domain logic in LiveViews.** LiveViews orchestrate; Ash actions decide.
- **Don't broadcast raw resource structs over PubSub.** Broadcast the minimum needed (id, type, scope) and let subscribers refetch via Ash if they need the full thing — keeps authorization honest. *Carve-out:* `Studysync.Chat.PubSub` (Slice 18) broadcasts the full `%Chat.Message{}` because chat is non-persistent — there's nothing to refetch from. This is the only place the rule is relaxed.
- **Don't expand the LiveView↔Svelte contract on a whim.** Updating §4.3 is part of the change.
- **Don't introduce a second Svelte component to "make life easier".** The cost of crossing that boundary repeatedly is higher than the cost of doing it well in LiveView once.
- **Don't reach past Ash to the Repo.** If Ash can't express it, that's a conversation, not a workaround.

---

## 9. Build priority (from REQUIREMENTS §12)

1. PDF Viewer + Text Selection
2. Annotation Creation + Display
3. Bi-directional Sync (PDF ↔ margin panel)
4. Annotation Threads
5. AI Integration
6. Milestone + Rubber Stamp System

Don't get ahead of the priority order without an explicit ask. Real-time, performance polish, and visual fidelity are continuous concerns layered across all six.

---

## 10. When in doubt

Ask. The user knows this domain and this stack deeply. A 30-second clarifying question beats a 30-minute wrong direction. Prefer one specific question over a list of three vague ones.

<!-- usage-rules-start -->
<!-- usage_rules-start -->

## usage_rules usage

_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should _thoroughly_ consult before taking any
action. These usage rules contain guidelines and rules _directly from the package authors_.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```

## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```

<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->

## usage_rules:elixir usage

# Elixir Core Usage Rules

## Pattern Matching

- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling

- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid

- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design

- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures

- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing

- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->

## usage_rules:otp usage

# OTP Usage Rules

## GenServer Best Practices

- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication

- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance

- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async

- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
