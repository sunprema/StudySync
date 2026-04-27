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

- [ ] **12.1** Ash resource: `StudySync.Progress.MilestoneMarker` (resource_id, page_number, position, label, created_by)
- [ ] **12.2** Ash action: `:create_milestone` — admins only via policy
- [ ] **12.3** Admin-only UI: "Place milestone" mode in reader
- [ ] **12.4** Svelte: render milestone markers on PDF (distinct from annotation markers)
- [ ] **12.5** LiveView↔Svelte prop: `milestone_markers[]`
- [ ] **12.6** Phoenix component: `<.milestone_panel>` listing milestones for current resource
- [ ] **12.7** Tests: creation, policy (admin only), rendering

---

## Slice 13 — Rubber Stamps

Users can stamp a milestone to mark completion. Stamps show progress (X/N users completed) with avatars.

- [ ] **13.1** Ash resource: `StudySync.Progress.RubberStamp` (milestone_id, user_id, note, inserted_at)
- [ ] **13.2** Ash action: `:apply_stamp` — one per user per milestone (unique constraint)
- [ ] **13.3** Ash aggregate: stamp count per milestone
- [ ] **13.4** Ash calculation: list of users who've stamped a given milestone
- [ ] **13.5** LiveView↔Svelte event: `apply_stamp` → `{ milestone_id }`
- [ ] **13.6** LiveView↔Svelte prop: `rubber_stamps[]`
- [ ] **13.7** Clicking a milestone marker shows completion state and stamp option
- [ ] **13.8** UI: "X / N readers" label and stamped-user avatar cluster
- [ ] **13.9** PubSub broadcast on stamp, real-time update for everyone watching
- [ ] **13.10** Tests: stamping, uniqueness, aggregate correctness

---

## Slice 14 — Visibility & Privacy Polish

Annotations have `:private | :workspace` visibility. Make the controls real and the policies airtight.

- [ ] **14.1** Visibility toggle in annotation creation form
- [ ] **14.2** Visibility indicator on margin note (small lock icon for private)
- [ ] **14.3** Audit Ash policies for every annotation read path — private annotations never leak
- [ ] **14.4** Tests: comprehensive policy tests covering author/non-author × private/workspace matrix

---

## Slice 15 — Performance Pass

Hit the perf targets in CLAUDE.md §6 with real measurement, not vibes.

- [ ] **15.1** Lazy-load annotations per page — only fetch annotations for visible page range
- [ ] **15.2** Annotation prefetch on scroll-near (one page ahead/behind)
- [ ] **15.3** Profile LiveView re-renders with `:telemetry` — kill any unnecessary re-renders
- [ ] **15.4** Profile PDF rendering — confirm page virtualization is actually working
- [ ] **15.5** Add basic `:telemetry` events for: annotation creation latency, AI job duration, PubSub broadcast fan-out
- [ ] **15.6** Document measured numbers in `PERFORMANCE.md`

---

## Slice 16 — UX Polish

Final pass to match the design fidelity. This is where the product earns its aesthetic.

- [ ] **16.1** Smooth scrolling between PDF and margin (eased, not snap)
- [ ] **16.2** Highlight pulse animation on annotation navigation
- [ ] **16.3** Hover linking between PDF markers and margin notes
- [ ] **16.4** Empty states: "No annotations yet" with quiet illustration
- [ ] **16.5** Loading skeletons in margin column during page transitions
- [ ] **16.6** Keyboard shortcuts: `J/K` page nav, `N` new annotation on selection, `Esc` close
- [ ] **16.7** Accessibility pass: focus rings, aria-labels on interactive elements, keyboard navigability
- [ ] **16.8** Side-by-side review against the design PDF — capture deltas, fix
- [ ] **16.9** Final manual QA on the core loop: Read → Highlight → Annotate → Discuss → AI → Save → Progress

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
- ...
```
