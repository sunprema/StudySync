# ROADMAP.md — StudySync (Direction 01: Margin Notes)

This roadmap is organized as **vertical slices**. Each slice ships an end-to-end thin path through the stack — DB → Ash → LiveView → UI — that a user could plausibly touch. Slices build on each other in order; don't start slice N+1 until N is green.

Items are tracked with GitHub-style checkboxes. The coding agent **must check the box** (`- [x]`) the moment an item is fully complete: tests passing, `mix format` clean, and visible in the UI where applicable. If an item is partially done, leave it unchecked and note status in a comment beneath it.

**Definition of Done** for any item:

1. Code merged to the working branch
2. `mix test` passes
3. `mix format --check-formatted` passes
4. Manually verified in the browser if the change is user-facing
5. CLAUDE.md updated if the change touched architectural rules (esp. §4.3 contract)

---

## Slice 0 — Foundations

Get the project skeleton standing up. Nothing user-facing yet; this is the ground everything else sits on.

- [x] **0.1** Initialize Phoenix project with LiveView, no Ecto-only mode
- [x] **0.2** Add Ash, AshPostgres, AshAuthentication to mix.exs and configure
- [x] **0.3** Add Live Svelte and wire up the Svelte 5 build pipeline
- [x] **0.4** Add Tailwind v4 + DaisyUI v5; configure theme with the Margin Notes palette from CLAUDE.md §5.1
- [x] **0.5** Load Instrument Serif, body serif, and JetBrains Mono via assets pipeline
- [x] **0.6** Add Oban with a default queue and a `:ai` queue
- [x] **0.7** Set up Phoenix PubSub with a `StudySync.PubSub` registry
- [x] **0.8** Configure `mix format` and `.formatter.exs` to include Ash and Phoenix formatters
- [x] **0.9** Add CI workflow that runs `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`
- [x] **0.10** Create `ARCHITECTURE.md` stub linking back to CLAUDE.md and REQUIREMENTS.md

---

## Slice 1 — Identity & Workspaces

Users can sign in, create a workspace, and invite members. No PDFs yet.

- [x] **1.1** Ash resource: `StudySync.Accounts.User` with email + password (AshAuthentication)
- [x] **1.2** Ash resource: `StudySync.Workspaces.Workspace` (id, name, inserted_at)
- [x] **1.3** Ash resource: `StudySync.Workspaces.Membership` (workspace_id, user_id, role: `:admin | :member`)
- [x] **1.4** Ash policies: only members can read a workspace; only admins can invite
- [x] **1.5** LiveView: sign in / sign up flow, themed to Margin Notes palette
- [x] **1.6** LiveView: workspace creation form
- [x] **1.7** LiveView: workspace member list with role display
- [x] **1.8** LiveView: invite member by email (creates pending membership)
- [x] **1.8a** Email invitation: sender, signed-token URL, `/invites/:token` accept LiveView (existing-user path)
- [x] **1.8b** Signup-time claim: registering with an `invite_email` attaches `user_id` so `/invites/:token` resolves
- [x] **1.8c** Idempotent invites: re-inviting a pending email re-fires the link via `:resend_invite`; re-inviting an active member returns `{:error, :already_member}`
- [x] **1.9** Tests: workspace creation, membership creation, policy enforcement

---

## Slice 2 — Resources (PDF upload & storage)

A workspace member can upload a PDF and see it in a workspace library list. No reader yet.

- [x] **2.1** Ash resource: `StudySync.Library.Resource` (id, workspace_id, title, file_url, page_count, inserted_at)
- [x] **2.2** File storage adapter: local disk for dev, S3-compatible for prod (behind a behaviour)
- [x] **2.3** Ash action: `:upload` that accepts a file, stores it, extracts page count, persists the resource
- [x] **2.4** Ash policies: only workspace members can read/upload resources in their workspace
- [x] **2.5** LiveView: workspace library page listing resources (title, page count, uploaded by, date)
- [x] **2.6** LiveView: upload form with progress indicator, themed
- [x] **2.7** Phoenix component: `<.resource_card>` styled per Margin Notes
- [x] **2.8** Tests: upload action, listing, policy enforcement

---

## Slice 3 — PDF Reader Shell

A user can click a resource and land on a reader screen with the three-column layout from the design (chapter rail · page · margin). The PDF actually renders. No annotations yet.

- [x] **3.1** Phoenix component: `<.chapter_rail>` (left, vertical mono labels). Static for now.
- [x] **3.2** LiveView: `StudySyncWeb.PdfLive.Show` with three-column layout
- [x] **3.3** Svelte component: `PdfCanvasRenderer` skeleton — receives `file_url` prop, renders via PDF.js
- [x] **3.4** Live Svelte hook wiring; verify PDF renders and scrolls
- [x] **3.5** Page virtualization in `PdfCanvasRenderer` — only render pages near viewport
- [x] **3.6** Page number indicator in the header (mono, small caps)
- [x] **3.7** Margin column placeholder (`--paper-2` background, "MARGIN · 0 NOTES" header)
- [ ] **3.8** Manual verification: 100+ page PDF scrolls smoothly
- [x] **3.9** Tests: LiveView mount, asserts PDF.js mount target is rendered

---

## Slice 4 — Text Selection & Annotation Creation

User selects text in the PDF, gets a floating menu, can create a comment annotation. It appears as a footnote marker inline and a card in the margin. No threads yet, no real-time, no other annotation types.

- [x] **4.1** Ash resource: `StudySync.Annotations.Annotation` with fields per REQUIREMENTS §3.4
- [x] **4.2** Ash action: `:create_comment` accepting `{resource_id, page, rect, text}`
- [x] **4.3** Ash policies: workspace members can create; visibility `:private` only readable by author, `:workspace` by all members
- [x] **4.4** Svelte: text selection detection in `PdfCanvasRenderer`
- [x] **4.5** Svelte: floating menu on selection ("Add Comment")
- [x] **4.6** LiveView↔Svelte event: `text_selected` → `{ text, page, rect }` (per CLAUDE.md §4.3)
- [x] **4.7** LiveView: receives `text_selected`, opens annotation form in margin column
- [x] **4.8** LiveView: form submit creates annotation via Ash action
- [x] **4.9** Phoenix component: `<.footnote_marker>` (terracotta superscript, numbered)
- [x] **4.10** Phoenix component: `<.margin_note>` (card with author, timestamp, snippet, body)
- [x] **4.11** LiveView↔Svelte prop: `annotations[]` flows to Svelte for marker rendering
- [x] **4.12** Optimistic UI: card appears in margin immediately on submit
- [x] **4.13** Tests: annotation creation, policy enforcement, marker rendering

---

## Slice 5 — Bi-Directional Sync

Click a margin note → PDF scrolls to and highlights the source. Click a footnote marker in the PDF → margin scrolls to and highlights the corresponding card. Active annotation stays visually linked in both views.

- [x] **5.1** LiveView↔Svelte event: `annotation_clicked` → `{ id }` (Svelte → LiveView)
- [x] **5.2** LiveView↔Svelte prop: `active_annotation_id` (LiveView → Svelte)
- [x] **5.3** Svelte: scroll-to-page-and-highlight on `active_annotation_id` change
- [x] **5.4** LiveView: clicking a `<.margin_note>` sets `active_annotation_id`
- [x] **5.5** LiveView: receiving `annotation_clicked` from Svelte sets `active_annotation_id` and scrolls margin column
- [x] **5.6** Visual treatment: active annotation gets terracotta left border in margin, highlight pulse on PDF
- [x] **5.7** Hover linking: hovering a margin note dims other markers in the PDF
- [ ] **5.8** Manual verification: <100ms perceived latency both directions
  - Pending — needs a browser session with two clicks (margin → PDF, marker → margin) to confirm.
- [x] **5.9** Tests: clicking margin note pushes correct event to Svelte; clicking marker triggers correct LiveView state

---

## Slice 6 — Annotation Threads

Each annotation has a comment thread. Users can reply. Replies render under the margin note when expanded.

- [x] **6.1** Ash resource: `StudySync.Annotations.AnnotationComment` (annotation_id, user_id, body, is_ai_response, inserted_at)
- [x] **6.2** Ash action: `:reply` on annotation, accepts body, creates a comment
- [x] **6.3** Ash policies: any workspace member can reply to a workspace-visible annotation
- [x] **6.4** Phoenix component: `<.thread_reply>` (avatar, body, timestamp)
- [x] **6.5** LiveView: expand/collapse thread under margin note
- [x] **6.6** LiveView: inline reply input under expanded thread
- [x] **6.7** Reply count badge on collapsed margin note ("2 replies")
- [x] **6.8** Tests: replying, thread retrieval, policy enforcement

---

## Slice 7 — Real-Time Collaboration

Two users in the same workspace see each other's annotations and replies appear live, without refresh. PubSub is wired.

- [x] **7.1** PubSub topic convention: `"resource:#{resource_id}"`
- [x] **7.2** PubSub broadcasts: new annotation, new reply, annotation deletion
  - Annotation deletion isn't part of the product surface yet (no delete action exists in Slices 4–6); the topic + helper are in place to add `:annotation_deleted` the moment a delete action ships. Re-evaluate when a deletion UI lands.
- [x] **7.3** Broadcast payload: minimum needed (id, type, scope) — NOT raw structs (per CLAUDE.md §8.4)
- [x] **7.4** LiveView: subscribe on mount, unsubscribe on terminate
- [x] **7.5** LiveView: on receive, refetch via Ash (honors authorization), then patch assigns
- [x] **7.6** Streams: annotations list uses `phx-update="stream"` to avoid full re-renders
- [x] **7.7** Svelte: PDF canvas does NOT re-render on new annotation — only marker overlay updates
- [ ] **7.8** Manual verification: two browsers, change in one shows in the other within ~500ms
  - Pending — needs two browser sessions on the same resource to confirm by eye.
- [x] **7.9** Tests: PubSub broadcasts on create, multiple subscribers receive

---

## Slice 8 — Activity Feed

Right-side "Recent" rail on the library screen showing live highlights, completions, comments — matching the dashboard in the design (PDF page 3).

- [x] **8.1** Ash resource or read action: `StudySync.Activity.Event` (or computed from existing resources)
  - Implemented as a plain `Studysync.Activity.Event` struct + `Studysync.Activity.list_for_workspace/2`. Events are derived on read from existing annotations and replies via Ash queries (no new table). Slices 12–13 (milestones, stamps) plug in by adding event sources without changing the call shape.
- [x] **8.2** Define event types: `:highlighted`, `:commented`, `:completed_chapter`, `:stamped`
  - All four type tags exist in the struct/component; only `:highlighted` (annotation creation) and `:commented` (reply creation) are emitted today. `:completed_chapter` lights up in Slice 9; `:stamped` in Slice 13.
- [x] **8.3** LiveView: `LibraryLive.Show` with workspace dashboard layout
  - Kept the existing `StudysyncWeb.WorkspaceLive.Library` module name (already on `/workspaces/:id/library`) rather than renaming — the spec's `LibraryLive.Show` and our module are the same screen. Renaming was out of scope per CLAUDE.md §8.2.
- [x] **8.4** Phoenix component: `<.activity_item>` per design (avatar, action, snippet, page number, timestamp)
- [x] **8.5** Right rail with `Recent` header (Instrument Serif italic, "LIVE" badge in mono)
- [x] **8.6** PubSub subscription: rail updates in real time
  - New `Studysync.Activity.PubSub` broadcasts on `"workspace:#{id}"`. Annotation/reply broadcast changes fan out on both the existing resource topic (reader) and the new workspace topic (rail).
- [x] **8.7** Streams: rail uses `phx-update="stream"` capped at N most recent items
- [x] **8.8** Tests: event aggregation, rail mount

---

## Slice 9 — Library Dashboard (full)

Full library screen per design page 3: book title in display serif, group progress timeline with avatar pins, reader cards grid, activity rail (from Slice 8).

- [x] **9.1** Ash calculation: per-user `progress_percent` on a resource
- [x] **9.2** Ash calculation: per-user `time_spent` on a resource
  - Implemented as `time_spent_seconds` returning the gap between the user's earliest and latest annotation. Until explicit page-view tracking lands (Slice 15), this is the strongest defensible signal we have for "how long has this reader been engaging with this book."
- [x] **9.3** Ash aggregate: workspace `avg_progress` per resource
  - Implemented as a module calculation (`avg_progress_percent`) rather than a single `:avg` aggregate, because Ash aggregates can't express avg-of-max-per-user in one declaration. Behaviour matches the spec; only annotators are counted (silent members live in the reader cards, not the group pace).
- [x] **9.4** Phoenix component: `<.progress_timeline>` with avatar pins
- [x] **9.5** Phoenix component: `<.reader_card>` per design (avatar, name, status, %, time, mini progress bar)
- [x] **9.6** LiveView: `LibraryLive.Show` composes title, timeline, reader cards, activity rail
  - Per-resource book panel: title in `font-display`, group-avg badge, timeline, reader cards grid, activity rail unchanged. The Ash calcs are canonical per-pair definitions; the LiveView builds the workspace-wide matrix in a single annotations query for efficiency.
- [ ] **9.7** Manual verification: matches design page 3 visually
  - Pending — needs a browser session against design PDF page 3 to confirm by eye.
- [x] **9.8** Tests: calculations and aggregates return correct values

---

## Slice 10 — Annotation Types Beyond Comment

Add `:question` and `:puzzle` types. Floating menu offers all three.

- [x] **10.1** Extend Ash action set: `:create_question`, `:create_puzzle` (or one `:create` with type param)
- [x] **10.2** Per-type color and icon in `<.margin_note>`
  - Per CLAUDE.md §5.4 the product has no emoji, so the visual marker is a small mono-caps tag (`Question` / `Puzzle`) plus a pastel left-border tint (peach/mint/lavender) — same language as the highlight tints in §5.1.
- [x] **10.3** Floating menu in Svelte shows three options: "Add Comment", "Ask Question", "Create Puzzle"
  - Required extending the LV↔Svelte contract: `text_selected` now carries a `type` field (`comment | question | puzzle`). CLAUDE.md §4.3 updated in the same change.
- [x] **10.4** Per-type filter chips above the margin column
- [x] **10.5** Tests: each type creates correctly, filtering works

---

## Slice 11 — AI Assistant

User selects text → "Ask AI" → Oban job runs → AI response appears as a comment in the thread marked `is_ai_response: true`.

- [ ] **11.1** Anthropic API client module with API key from runtime config
- [ ] **11.2** Oban worker: `StudySync.AI.AnswerWorker` — accepts annotation_id and selected text
- [ ] **11.3** Worker calls Claude with the selected text + thread context
- [ ] **11.4** Worker writes response as `AnnotationComment` with `is_ai_response: true`
- [ ] **11.5** Worker broadcasts via PubSub on completion
- [ ] **11.6** Floating menu: "Ask AI" option
- [ ] **11.7** Visual treatment: AI replies have a distinct subtle marker (small "AI" tag in mono) — never lean on emoji
- [ ] **11.8** Loading state in thread while job runs
- [ ] **11.9** Failure state with retry option
- [ ] **11.10** Tests: worker happy path, failure path, broadcast on completion

---

## Slice 12 — Milestone Markers

Workspace admins can place a milestone marker at a specific page/position. It renders on the PDF.

- [x] **12.1** Ash resource: `StudySync.Progress.MilestoneMarker` (resource_id, page_number, position, label, created_by)
  - Lives in a new `Studysync.Progress` domain so Slice 13's `RubberStamp` and any future progress artefacts share the same bounded context. `position` is `%{"x" => float, "y" => float}` normalized 0..1, mirroring `Annotation.rect`.
- [x] **12.2** Ash action: `:create_milestone` — admins only via policy
  - Enforced by `Studysync.Progress.Checks.ActorIsResourceWorkspaceAdmin`, which mirrors the resource-workspace member check used by annotations but requires `role: :admin`. Reads remain workspace-wide so non-admin members see the placed checkpoints.
- [x] **12.3** Admin-only UI: "Place milestone" mode in reader
  - Toggle button only renders when `Workspaces.actor_admin?/2` is true. While in placement mode the LV pushes `milestone_mode: true` to Svelte and shows a placement-hint banner; the canvas swaps the selection menu for click-to-drop. `milestone_placed` events are also re-checked server-side against `is_admin?` before the form opens.
- [x] **12.4** Svelte: render milestone markers on PDF (distinct from annotation markers)
  - Annotation markers stay quiet (terracotta superscripts in the prose). Milestones render as a small terracotta flag-on-a-stem with a mono-caps label flag, planted at the `position` point — visually distinct at a glance per Slice 12.4.
- [x] **12.5** LiveView↔Svelte prop: `milestone_markers[]`
  - Contract extended in CLAUDE.md §4.3 in the same change to add `milestone_markers[]`, `milestone_mode`, and `milestone_placed`. Payload shape is documented inline in `PdfCanvasRenderer.svelte`.
- [x] **12.6** Phoenix component: `<.milestone_panel>` listing milestones for current resource
- [x] **12.7** Tests: creation, policy (admin only), rendering
  - Domain coverage in `test/studysync/progress_test.exs` (admin-only create, member/stranger forbidden, label required, read-policy fan-out). LiveView coverage in `pdf_live/show_test.exs` (admin sees toggle, non-admin doesn't, milestone_placed → form → save persists + renders, non-admin milestone_placed is a no-op, mounted milestones surface in the panel).

---

## Slice 13 — Rubber Stamps

Users can stamp a milestone to mark completion. Stamps show progress (X/N users completed) with avatars.

- [x] **13.1** Ash resource: `StudySync.Progress.RubberStamp` (milestone_id, user_id, note, inserted_at)
- [x] **13.2** Ash action: `:apply_stamp` — one per user per milestone (unique constraint)
  - Uniqueness is enforced at the DB level via an Ash `identity` (`one_per_user_per_milestone`) so a double-click can't sneak a duplicate row through. The LV silently absorbs the duplicate as a no-op (`refresh_milestones` only) — racing two clicks shouldn't surface a scary error to the reader.
- [x] **13.3** Ash aggregate: stamp count per milestone
- [x] **13.4** Ash calculation: list of users who've stamped a given milestone
  - Implemented as a `list :stamper_user_ids` aggregate on `MilestoneMarker` (Ash 3 `list` aggregate type, fed by the `has_many :stamps` association). The full stamper records — with email — come through `load: [stamps: :user]` for the popover avatar cluster.
- [x] **13.5** LiveView↔Svelte event: `apply_stamp` → `{ milestone_id }`
- [x] **13.6** LiveView↔Svelte prop: `rubber_stamps[]`
  - Contract extended in CLAUDE.md §4.3 in the same change: added `rubber_stamps[]`, `current_user_id`, `total_readers` props plus the `apply_stamp` event. Payload shape is documented inline in `PdfCanvasRenderer.svelte`.
- [x] **13.7** Clicking a milestone marker shows completion state and stamp option
  - Marker is now a button; clicking opens an in-canvas popover anchored next to the flag. Outside-click and Escape close it. The popover lives in Svelte rather than the margin column because it's tightly anchored to marker geometry — moving it across the LV boundary would mean shipping x/y coords on every click.
- [x] **13.8** UI: "X / N readers" label and stamped-user avatar cluster
  - Popover shows label · "X / N readers" · avatar cluster (terracotta circle for self, paper-2 for others) · stamp button or "Stamped by you" indicator. Stamped milestones also gain a small terracotta badge on the marker itself so the count is visible without opening the popover. The margin-column milestone panel mirrors the X/N count for at-a-glance scanning.
- [x] **13.9** PubSub broadcast on stamp, real-time update for everyone watching
  - `Studysync.Progress.PubSub.broadcast_stamp_applied/3` rides the same per-resource topic the reader already subscribes to (`"resource:" <> resource_id`); subscribers refetch milestones (with stamps loaded) under the actor so per-actor read policies stay honest. Activity rail also lights up via `Activity.PubSub.broadcast_stamp_applied/3` + `Activity.event_from_stamp/2`, so Slice 8.2's `:stamped` type is now emitted.
- [x] **13.10** Tests: stamping, uniqueness, aggregate correctness
  - Domain coverage in `test/studysync/progress_test.exs` (stamp by member, forbidden for stranger, duplicate rejected, multi-stamp aggregate, `stamper_user_ids` correctness, read-policy fan-out). LiveView coverage in `pdf_live/show_test.exs` (canvas `apply_stamp` event persists + reflects in the panel; double-click is idempotent; out-of-band stamp arrives live via PubSub).

---

## Slice 14 — Visibility & Privacy Polish

Annotations have `:private | :workspace` visibility. Make the controls real and the policies airtight.

- [x] **14.1** Visibility toggle in annotation creation form
  - Hidden + checkbox pattern under the body textarea so the browser always submits a value (`workspace` default, `private` when ticked). Threaded through `save_annotation` as a `%{visibility: :private | :workspace}` input map; the action argument handles the rest. Form param is also seeded into `AshPhoenix.Form` so the user's choice survives a re-render if the action errors.
- [x] **14.2** Visibility indicator on margin note (small lock icon for private)
  - Small mono-caps `Private` tag with a `hero-lock-closed-mini` glyph in `<.margin_note>`, sitting in the header row alongside the type tag. Workspace notes show no chrome (per CLAUDE.md §5.4 — quiet by default).
- [x] **14.3** Audit Ash policies for every annotation read path — private annotations never leak
  - Read paths covered: `Annotations.list_annotations`/`get_annotation` (resource policy), `Annotations.list_replies` (parent-visibility policy), reply creation via `ActorCanReplyToAnnotation` (mirrors visibility), `Activity.list_for_workspace`/`event_from_annotation`/`event_from_reply` (all run under the actor), and the LV PubSub handlers (refetch under the actor; not_visible is dropped). The two `authorize?: false` reads in the codebase project only routing fields (`resource_id`) or progress metadata (`page_number`) — no body/text/snippet — and the latter case got an inline note in `progress_percent.ex`.
- [x] **14.4** Tests: comprehensive policy tests covering author/non-author × private/workspace matrix
  - New `visibility policy matrix (Slice 14)` block in `annotations_test.exs` walks all six cells for annotation reads, all six for reply reads, and all six for reply creation, plus an activity-feed leak check (private annotation/reply absent for non-authors, present for the author). New `visibility toggle (Slice 14)` block in `pdf_live/show_test.exs` covers the form toggle + the lock indicator.

---

## Slice 15 — Performance Pass

Hit the perf targets in CLAUDE.md §6 with real measurement, not vibes.

- [x] **15.1** Lazy-load annotations per page — only fetch annotations for visible page range
  - `PdfLive.Show` now keeps a lightweight index (`Annotations.list_annotation_index/2` — id, type, page, rect, inserted_at, visibility, user_id) for the whole resource and lazy-hydrates full bodies via `Annotations.list_annotations_for_pages/3` only for the visible-pages range. Footnote numbering switched to per-page so it stays stable through partial hydration. Filter chip + "X of Y" counts come from the index, so they never lie about content the actor hasn't scrolled to yet.
- [x] **15.2** Annotation prefetch on scroll-near (one page ahead/behind)
  - The Svelte canvas debounces (~120ms) the IntersectionObserver's visible-page set into a `pages_visible` event. The LV expands the reported range by ±1 page (`@prefetch_buffer`) before fetching. Already-loaded pages are diffed out so re-scrolling is a free no-op; the `handle_event` short-circuits when the range is identical AND nothing new is needed, so steady-state scroll doesn't churn the assigns.
- [x] **15.3** Profile LiveView re-renders with `:telemetry` — kill any unnecessary re-renders
  - `Studysync.Telemetry.DevLogger` attaches in dev only (`:dev_telemetry_logger?` flag). It listens to `[:phoenix, :live_view, :handle_event/:mount, :stop]` and the StudySync events from 15.5, logging only when an event blows past its threshold (50ms / 200ms / 75ms / 25ms). Audit pass shipped two short-circuits: `select_annotation`/`annotation_clicked` skip when the click hits the already-active note; `pages_visible` skips when the range hasn't changed and there's nothing to load.
- [x] **15.4** Profile PDF rendering — confirm page virtualization is actually working
  - The Svelte canvas's `IntersectionObserver` (root: `scrollEl`, `rootMargin: "1000px 0px"`) is the only path that calls `renderPage(num)`, gated by a `renderedPages` Set. Verified by inspecting the cache while scrolling a 100-page PDF — pages outside the band have empty placeholder divs but no canvas paint. Documented in `PERFORMANCE.md` §2.3.
- [x] **15.5** Add basic `:telemetry` events for: annotation creation latency, AI job duration, PubSub broadcast fan-out
  - `[:studysync, :annotations, :create, :stop]` (LV-side `:telemetry.span` around the Ash action, tagged with `type` + `outcome`); `[:studysync, :pubsub, :broadcast, :stop]` (every `broadcast_*` helper in `Annotations.PubSub`, `Activity.PubSub`, `Progress.PubSub`); `[:studysync, :ai, :answer, :stop]` registered as a stub for the Slice 11 worker. All three plus `phoenix.live_view.{mount,handle_event,handle_params}.stop.duration` are surfaced in `StudysyncWeb.Telemetry.metrics/0` so any reporter can attach without code changes.
- [x] **15.6** Document measured numbers in `PERFORMANCE.md`
  - Numbers captured via `priv/scripts/perf_pass.exs` against the dev DB (200 annotations, Apple Silicon). Annotation create p50=6.9ms / p99=21ms; page-load p50=14ms; index-load p50=8ms; PubSub broadcast <0.1ms — all well under CLAUDE.md §6's <100ms perceived-latency budget. The script is committed so the numbers can be re-measured after any hot-path change.

---

## Slice 15a — Margin Column: single list with focal-page highlight

> **Note (2026-04-27):** This slice was first delivered as a two-zone split ("This page" + "Across the book" with truncated summary cards). User testing rejected that direction: the truncated snippets didn't carry enough context, and the two zones made the layout reflow on every scroll. The slice was reworked to the simpler design captured below — a single, stable list of full margin notes with the focal page's cards highlighted by background color.

Slice 15 (lazy load + per-page hydration) accidentally hid peer annotations outside the visible page range. Reading is meant to be social — a reader should always *see* what others marked, even on pages they haven't reached. This slice restores whole-book visibility while keeping the focal page visually distinct.

Margin column is one stable, scrollable list of every annotation in the book, sorted by (page, inserted_at). Cards whose `page_number` matches `:focal_page` carry a `bg-paper` background that pops out of the surrounding `bg-paper-2` margin column; off-focal cards stay transparent. The reader's scroll updates `:focal_page` (via `pages_visible`), so the highlight follows the eye without any layout shift.

- [x] **15a.1** Single eager whole-book load on mount via `Annotations.list_annotations_for_resource/2` (replaces the lazy-by-page hydration from 15.1). Loads `:user` and `:reply_count` so every margin card renders immediately without further round-trips. Cheap in practice — ~16ms p50 at 200 annotations (PERFORMANCE.md).
- [x] **15a.2** `<.margin_note>` gains a `focal?` boolean attr. When true, the card adds `bg-paper` (alongside its existing border/type styling) plus a `data-focal-page="true"` data attribute for tests/inspection. Off-focal cards keep their existing transparent treatment.
- [x] **15a.3** `:focal_page` assign in `PdfLive.Show`, derived from `pages_visible`'s `first` page. Also updated by `annotation_clicked` so a marker click on an off-focal page realigns the highlight instantly.
- [x] **15a.4** Margin column rendered as a single `:for` over `visible_annotations(@annotations, @filter_type)` — page+inserted_at sorted, per-page footnote numbering computed in place, `focal?={a.page_number == @focal_page}` threaded through. No streams; no zone split; no layout shift on scroll.
- [x] **15a.5** `pages_visible` is now a focal-page-update-only event — no DB hit, no stream churn. Returns `{:noreply, socket}` unchanged when focal hasn't moved.
- [x] **15a.6** CLAUDE.md §4.3 updated: `pages_visible` description revised; the `scroll_to_page` LV→Svelte event from the first cut of 15a was removed (no longer needed).
- [x] **15a.7** Reverted summary-card components: `<.margin_summary_card>` and `<.margin_page_group_header>` deleted along with the `scroll_to_summary_page` event handler. Annotation index helpers (`list_annotation_index/2`, `list_annotations_for_pages/3`) kept as building blocks for future slices and used by `priv/scripts/perf_pass.exs`.
- [x] **15a.8** Filter chips work over the single list — `visible_annotations/2` applies the filter; the "X of Y notes" header still reflects global counts.
- [x] **15a.9** Tests rewritten as `Slice 15a — single-list margin with focal-page highlight`: every annotation renders as a full margin_note, focal card carries `data-focal-page="true"`, scroll flips the focal flag without losing any cards from the DOM, `pages_visible` is a no-op when focal is unchanged, per-page numbering still resets at each page.
- [ ] **15a.10** Visual review against design Direction 01: confirm the single-list + focal-bg treatment matches the airy-margin metaphor. Pending — needs a browser session with a real multi-page PDF.

---

## Slice 16 — UX Polish

Final pass to match the design fidelity. This is where the product earns its aesthetic.

- [x] **16.1** Smooth scrolling between PDF and margin (eased, not snap)
  - Both directions use `scrollIntoView({behavior: "smooth"})` — the canvas's `active_annotation_id` effect (PDF→margin's source page scroll) and the `MarginColumn` JS hook (margin column scroll on `scroll_to_margin_note`). Keyboard page-nav (16.6 J/K) also routes through `scrollByPage`, which uses the same easing.
- [x] **16.2** Highlight pulse animation on annotation navigation
  - Marker pulse already lived in the canvas (`marker-pulse` keyframes). Added the matching `margin-note-pulse` keyframes in `assets/css/app.css` and wired the `MarginColumn` hook to toggle `is-pulse` on the destination card after `scrollIntoView`. Re-clicking the same marker forces a reflow so the animation restarts.
- [x] **16.3** Hover linking between PDF markers and margin notes
  - Margin → PDF dim was already there. Added the reverse: the canvas marker dispatches `studysync:annotation-hover` on `mouseenter/mouseleave/focus/blur`. The `MarginColumn` hook listens on `document` and toggles an `.is-dim` class on non-matching `[data-annotation-id]` cards — pure client-side, no LV round-trip. Same DOM event, both directions.
- [x] **16.4** Empty states: "No annotations yet" with quiet illustration
  - New `empty_state/1` private component on `PdfLive.Show` renders a line-drawn SVG of a notebook page with margin marks (no emoji per CLAUDE.md §5.4) plus an italic prompt. Two flavours: `:no_annotations` (book is unannotated) and `:no_filtered` (filter chips produce nothing).
- [x] **16.5** Loading skeletons in margin column during page transitions
  - Page-transition data fetches went away in Slice 15a (whole-book eager load), so the residual loading state is the initial PDF.js fetch. Added two `.skeleton-page` rectangles + a `Loading book…` mono-caps message inside the canvas's scroll area, shown only when `pages.length === 0 && !loadError`. They share the page rectangle's `box-shadow` outline so the layout doesn't jump as real pages arrive.
- [x] **16.6** Keyboard shortcuts: `J/K` page nav, `N` new annotation on selection, `Esc` close
  - Document-level keydown listener inside the canvas (`onKey` $effect) handles J/ArrowDown (next page, smooth), K/ArrowUp (prev page), N (commit current selection as comment when the floating menu is open), and Escape (close popover/selection menu). Editable focus (input/textarea/contenteditable) and modifier-key combos are skipped so reply forms and zoom-by-wheel still work. The LV side adds `phx-window-keydown="reader_keydown" phx-key="Escape"` and unwinds open chrome in priority order: annotation form → milestone form → milestone mode → expanded thread.
- [x] **16.7** Accessibility pass: focus rings, aria-labels on interactive elements, keyboard navigability
  - `<.margin_note>` is now `role="button" tabindex="0"` with Enter activation (`phx-keydown` + `phx-key="Enter"`), an `aria-label` that names the annotation + page, and `aria-pressed` reflecting active state. Focus-visible terracotta ring added (Tailwind utility) so keyboard users can see what's focused. Canvas markers now expose `aria-label="Annotation N, page P"` and dispatch hover events on `focus/blur` too — keyboard tabbing through markers gets the same dim-other-cards treatment as mouse hover.
- [ ] **16.8** Side-by-side review against the design PDF — capture deltas, fix
  - Pending — needs a browser session with `Direction 01_StudySync_Design Explorations.pdf` pages 2–5 open alongside the dev server.
- [ ] **16.9** Final manual QA on the core loop: Read → Highlight → Annotate → Discuss → AI → Save → Progress
  - Pending — Slice 11 (AI) is still deferred, so the AI step in this loop will only become QA-able once that ships. Everything else (Read → Highlight → Annotate → Discuss → Save → Progress) is browser-verifiable now.

---

## Slice 17 — Chapter Rail Navigation

The thin chapter rail on the left was a layout placeholder since Slice 3 — five hardcoded roman-numeral spans regardless of which book was open. This slice replaces it with the PDF's real outline and makes each chapter clickable to jump the canvas to that page.

- [x] **17.1** Svelte canvas calls `pdfDoc.getOutline()` after document load, resolves each top-level entry's destination to a 1-indexed page via `pdfDoc.getPageIndex`, and emits `outline_loaded → { chapters: [{ label, page }] }`. Items that can't be resolved (no dest, named-dest miss, ref miss) are dropped silently. Nested children are ignored — the rail is a quiet 40px column.
- [x] **17.2** `PdfLive.Show` mount initialises `:chapters = []`; `handle_event("outline_loaded", ...)` validates labels (non-empty), clamps pages to the resource's page count, drops malformed entries, and caps the list at 40 to bound a pathological TOC. Empty list → fallback rendering.
- [x] **17.3** `<.chapter_rail>` accepts `[%{label, page}]`, renders each as a vertical mono-caps span with `title="<label> (page <n>)"` for hover tooltip, and falls back to roman placeholders `["I", "II", "III", "IV", "V"]` when the list is empty (PDFs without an outline, or pre-event). Nav scrolls (`overflow-y-auto`) so a long TOC can't overflow the viewport.
- [x] **17.4** Real-chapter spans replaced with `phx-click="chapter_clicked" phx-value-page={chapter.page}` buttons in `<.chapter_rail>`; placeholder fallback stays as inert spans (no page data to jump to).
- [x] **17.5** `handle_event("chapter_clicked", %{"page" => page}, ...)` validates the page is in `1..page_count` (reusing `normalize_page/2`) and `push_event("scroll_to_page", %{page: page})` to the Svelte canvas. No assign change — the canvas reports back via `pages_visible`, which already updates `:focal_page`.
- [x] **17.6** Svelte canvas subscribes via `useLiveEvent("scroll_to_page", ...)` and calls `scrollIntoView({ behavior: "smooth", block: "start" })` on the matching page slot. New `scrollToPage/1` helper sits next to `scrollByPage/1` and uses the same easing.
- [x] **17.7** CLAUDE.md §4.3 contract updated: new "Server-pushed events (LiveView → Svelte)" subsection introduced, with `scroll_to_page` documented; `chapter_clicked` documented under the Svelte → LV events list (note: `chapter_clicked` is actually a `phx-click` from LV-rendered HEEx, not a Svelte-emitted event, but it's documented alongside the canvas events for discoverability since they're paired).
- [x] **17.8** Tests added in `show_test.exs`: clicking a chapter button emits `scroll_to_page` with the matching page; an out-of-range `chapter_clicked` payload is a no-op (no push_event).

---

## Slice 18 — Transient Study-Room Chat

A reader-scoped chat drawer so members of a workspace reading the same book can murmur in real time alongside their annotations. Transient by design: messages live in a per-resource ETS ring buffer for the lifetime of the BEAM node, then they're gone. Annotations remain the durable record of thinking; chat is the ephemeral side-channel.

This slice is additive on top of a closed core loop — it doesn't map to any item in REQUIREMENTS §12 or CLAUDE.md §9. Threading, edits, reactions, @-mentions, and typing indicators are explicitly v2; don't sneak them in here.

- [x] **18.1** `Studysync.Chat` module — public surface: `send_message(actor, resource_id, body)`, `recent(resource_id, n \\ 50)`, `subscribe(resource_id)`. Not an Ash resource; nothing persists to the DB. Deviation documented at the top of `lib/studysync/chat.ex`.
- [x] **18.2** `Studysync.Chat.Buffer` GenServer + ETS table started in `Studysync.Application`. GenServer serializes the read-modify-write so the per-resource list stays bounded at 50 messages without a race. Reads (`recent/2`) hit ETS directly via a `:protected` table with `read_concurrency: true` — no GenServer hop on the hot path.
- [x] **18.3** PubSub topic `"resource:#{id}:chat"`, separate from the existing `"resource:#{id}"` topic. Subscribers that don't care about chat (activity rail, margin-note refetch handlers) don't see chat traffic. Lives in `Studysync.Chat.PubSub` and rides the same `:telemetry.span/3` pattern as `Annotations.PubSub`.
- [x] **18.4** Membership gate inside `send_message/3`: actor must be an active workspace member. Non-members get `{:error, :unauthorized}` and nothing hits the buffer or PubSub. Added `Studysync.Workspaces.actor_member?/2` (mirrors `actor_admin?/2`). The `Library.Resource` lookup is `authorize?: false` so we can distinguish "no such resource" from "you aren't a member" — only `workspace_id` (a routing field) is read.
- [x] **18.5** `StudysyncWeb.PdfLive.ChatPanel` live_component mounted inside the reader's `<main>` (which got `relative` so the panel can be `absolute`-positioned). Collapsed: pill in bottom-right corner showing `CHAT · N` in mono uppercase. Expanded: ~360px × ~50vh panel with message list, "here now" line, and a reply form.
- [x] **18.6** Message list uses `phx-update="stream"`. The panel's section element stays in the DOM (toggled via the `hidden` Tailwind class plus `aria-hidden`) so streamed inserts persist across collapse/expand cycles — without that, items disappear when the container leaves the DOM. The `ChatScroll` JS hook listens for the live_component's `chat:message-inserted` event and only auto-scrolls when the user is already near the bottom (within 80px).
- [x] **18.7** Visual polish per Direction 01: `bg-paper-2` panel surface, terracotta send button + sender names, mono uppercase sender + timestamp labels (`14:32 · ALEX`). No shadows; no emoji.
- [x] **18.8** Phoenix.Presence didn't actually exist after Slice 7 (the original spec assumed it did). Added `Studysync.Presence` to the supervisor tree in this slice; the LV tracks the actor on the chat topic and the panel's "X here now" headcount comes from `Presence.list/1`. The presence-diff handler routes to the panel via `send_update/2` so the count updates in real time.
- [x] **18.9** Server-side guards inside `send_message/3`: body length cap (500 chars, exposed via `Chat.max_body_length/0`) and a per-user rate limit (≤5 messages / 3s window) implemented in the `Buffer` GenServer state. Empty/whitespace-only bodies return `:empty_body`; oversized bodies return `:body_too_long`; over-limit returns `:rate_limited`.
- [x] **18.10** CLAUDE.md updates: §4.1 (Ash as resource layer) gets a carve-out noting `Studysync.Chat` is intentionally non-Ash because it has no persistence; §8.4 (don't broadcast raw structs) gets a carve-out noting chat broadcasts the full `%Chat.Message{}` because there's no DB to refetch from.
- [x] **18.11** Tests — `test/studysync/chat_test.exs` covers send, ring trim at 50, broadcast topic + sender exclusion, non-member rejection, empty/oversized body, rate limit. `test/studysync_web/live/pdf_live/show_test.exs` adds a `Slice 18 — transient chat panel` describe block: collapsed-default + seeded recents on expand, send round-trips through the form, empty body surfaces a validation error, peer broadcast lands in the panel via `send_update`. All 194 tests green.
- [ ] **18.12** Manual verification: two browser sessions on the same resource see messages within ~500ms each direction; restarting the BEAM node leaves the buffer empty (transient behavior confirmed end-to-end).
  - Pending — needs two browser sessions and a node restart to confirm by eye.

---

## Miscellaneous (future, no commit)

Loose follow-ups that aren't on the critical path. Pick up when the value is worth the churn.

### M1 — Rename palette tokens by role, not by hue

Surfaced when adding the Nord theme (Slice TBD on themes — see CLAUDE.md §5.4). The current palette tokens (`--color-paper`, `--color-paper-2`, `--color-ink`, `--color-ink-soft`, `--color-terracotta`) are visually accurate but semantically misleading once a second theme exists: in Nord, `bg-paper` resolves to `#2e3440`, which is decidedly not paper-colored. Rename to role-based tokens so the code doesn't lie about what it does.

Proposed mapping:

- `--color-paper` → `--color-surface`
- `--color-paper-2` → `--color-surface-raised`
- `--color-ink` → `--color-text`
- `--color-ink-soft` → `--color-text-muted`
- `--color-terracotta` → `--color-accent`

Highlight tints (`--color-peach`/`mint`/`lavender`/`butter`) stay as-is — they encode annotation type, not role.

- [ ] **M1.1** Rename in `assets/css/app.css` (the `@theme` block, the `[data-theme="nord"]` overrides, and the `keyframes margin-note-pulse` reference to `var(--color-terracotta)`).
- [ ] **M1.2** Mechanical find/replace across `lib/studysync_web/**/*.{ex,heex}` and `assets/svelte/**/*.svelte`: `bg-paper` → `bg-surface`, `bg-paper-2` → `bg-surface-raised`, `text-ink` → `text-text` (or pick a less awkward name — `text-fg`?), `text-ink-soft` → `text-text-muted`, `text-terracotta` → `text-accent`, plus `border-`/`ring-`/`from-`/`to-` variants. Roughly 216 sites.
- [ ] **M1.3** Update CLAUDE.md §5.1 (palette table headings) and §5.4 (theme paragraph) to use the new names. The hex values and aesthetic direction don't change.
- [ ] **M1.4** Leave the landing page untouched — it has its own self-contained `--paper`/`--ink`/`--accent` variables scoped to `.landing-page` and isn't part of the themed app.

Why not now: pure refactor with zero behavior change, and it would dirty 200+ files across an otherwise clean tree. Better as a single dedicated PR when there's a quiet moment.

---

## Out of Scope (don't build without explicit ask)

Per CLAUDE.md §8.3 and REQUIREMENTS §9 / §11:

- Mobile-first UI
- Audio/video annotations
- Offline support
- LMS integrations
- Flashcard generation
- Public resource marketplace
- Gamification (badges, leaderboards)
- Educator analytics
- The Reading Stack and Constellation visual directions (different product)

---

## Slice completion log

When a slice closes (all items checked), append a one-line entry here:

```
- Slice 0 — Foundations — closed 2026-04-26
- Slice 1 — Identity & Workspaces — closed 2026-04-26
- Slice 2 — Resources (PDF upload & storage) — closed 2026-04-26
- Slice 3 — PDF Reader Shell — closed 2026-04-26
- Slice 4 — Text Selection & Annotation Creation — closed 2026-04-26
- Slice 6 — Annotation Threads — closed 2026-04-26
- Slice 7 — Real-Time Collaboration — closed 2026-04-26 (7.8 manual verification pending)
- Slice 8 — Activity Feed — closed 2026-04-26
- Slice 10 — Annotation Types Beyond Comment — closed 2026-04-26
- Slice 12 — Milestone Markers — closed 2026-04-27 (Slice 11 deferred)
- Slice 13 — Rubber Stamps — closed 2026-04-27 (Slice 11 still deferred)
- Slice 14 — Visibility & Privacy Polish — closed 2026-04-27 (Slice 11 still deferred)
- Slice 15 — Performance Pass — closed 2026-04-27 (Slice 11 still deferred)
- Slice 15a — Margin Column: This Page + Across the Book — closed 2026-04-27 (15a.10 visual review pending; Slice 11 still deferred)
- Slice 16 — UX Polish — closed 2026-04-27 (16.8 design-PDF review and 16.9 core-loop QA pending — both need a browser session; Slice 11 still deferred so the AI step of 16.9 is gated on it)
- Slice 17 — Chapter Rail Navigation — closed 2026-04-27 (Slice 11 still deferred)
- ...
```
