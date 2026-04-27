# PERFORMANCE.md

Slice 15 perf-pass results and the architectural guarantees behind them. The
budgets come from `CLAUDE.md` §6; the numbers come from `priv/scripts/perf_pass.exs`
run against the dev database. The telemetry contract is documented at the
end so reporters or alerting can attach without re-deriving it.

If you change a hot path, re-run the bench and update the numbers in §3.

## 1. Budgets (from CLAUDE.md §6)

| Concern                        | Target                            |
| ------------------------------ | --------------------------------- |
| Perceived interaction latency  | <100ms                            |
| Annotations on mount           | Lazy per page — never the whole book |
| LiveView re-renders            | Scoped (streams; no full diffs)   |
| PDF rendering                  | Page virtualization (only near-viewport pages painted) |
| Highlight overlay drawing      | Svelte-side (LV pushes data)      |

## 2. Architecture: how each budget is met

### 2.1 Lazy annotation loading (Slices 15.1, 15.2)

The reader doesn't fetch the whole book's annotations at mount.
`StudysyncWeb.PdfLive.Show.mount/3` loads two things only:

1. A **lightweight index** via `Annotations.list_annotation_index/2` — id,
   type, page, rect, inserted_at, visibility, user_id (no body, no text,
   no replies). Drives Svelte markers, filter-chip counts, and per-page
   footnote numbering.
2. **Full annotations for the initial visible range** (pages
   `1..min(3, page_count)`) via `Annotations.list_annotations_for_pages/3`.
   This populates `@annotations_by_id` and the margin stream.

Subsequently, `PdfCanvasRenderer.svelte` reports the visible page range
back to LiveView via the `pages_visible` event (debounced ~120ms,
de-duped). The LV expands by the prefetch buffer (±1 page) and only
fetches pages it hasn't already loaded. Re-scrolling to a previously
visible page is free — the rows are already in `@annotations_by_id`.

Footnote numbering is **per-page** (¹ ² ³ resets each page) so it stays
stable across lazy hydration; it doesn't depend on global ordering.

### 2.2 LiveView re-render discipline (Slice 15.3)

Hot paths that fire on every scroll, every click, or on PubSub bursts
guard against unnecessary diffs:

- `handle_event("pages_visible", ...)` returns `{:noreply, socket}`
  unchanged when the visible range is identical to the last report
  *and* there's nothing new to load. Lib: `lib/studysync_web/live/pdf_live/show.ex`.
- `handle_event("select_annotation", ...)` and `"annotation_clicked"`
  short-circuit when the click landed on the already-active note.
- The margin column is a `phx-update="stream"` so a single
  `stream_insert/3` updates one card without re-rendering the rest.
- Annotation index broadcasts carry `{id, resource_id}` only — never the
  full row — so subscribers refetch only what they need under their own
  actor (CLAUDE.md §8.4).

### 2.3 PDF page virtualization (Slice 15.4)

`PdfCanvasRenderer.svelte` allocates an empty `<div class="page">`
placeholder for every page (so scrollbar geometry is correct) but only
*paints* canvases for pages within `1000px` of the viewport. The
`IntersectionObserver` (root: `scrollEl`, `rootMargin: "1000px 0px"`)
calls `renderPage(num)` exactly once per (page, zoom) tuple — the
`renderedPages` Set is the cache. Zoom changes clear the cache and re-paint
only pages currently near the viewport.

Verified by inspecting `renderedPages` while scrolling a 100-page PDF in
the dev session: pages outside the ±1000px band remain unrendered (their
canvases retain the default 0×0 dimensions; only the placeholder div is
in the DOM).

## 3. Measured numbers

Captured via `MIX_ENV=dev mix run priv/scripts/perf_pass.exs` against the
dev Postgres at localhost:5433, on Apple Silicon. The script provisions a
clean workspace, creates 200 annotations, and times the four hot paths.

Re-run after any change that touches the Ash actions, indexes, or PubSub
topology. Numbers should not regress.

| Path                                        | n   | p50    | p95    | p99    | max    | avg    |
| ------------------------------------------- | --- | ------ | ------ | ------ | ------ | ------ |
| `annotation_create` (Ash action + PubSub)   | 200 | 6.9ms  | 13.5ms | 21.4ms | 91.4ms | 7.9ms  |
| `page_load` (full bodies for 1 page, ~67 rows) | 50  | 13.8ms | 26.9ms | 47.2ms | 47.2ms | 16.5ms |
| `index_load` (whole-resource lightweight stub, 200 rows) | 50 | 7.8ms | 14.6ms | 17.9ms | 17.9ms | 8.4ms |
| `pubsub_broadcast` (0 subscribers)          | 200 | <0.1ms | <0.1ms | <0.1ms | 0.06ms | <0.1ms |

Notes on what these mean:

- **Annotation create** clears the <100ms perceived-latency budget at
  every percentile up to p99. The single 91ms outlier was the first call
  after a query plan refresh (cold cache); subsequent runs cluster
  around p50.
- **Page load** is the lazy-hydration query that fires on
  `pages_visible`. With 200 rows distributed across 3 pages, each page
  load returns ~67 rows including `:user` and the `:reply_count`
  aggregate. p95=27ms is well under budget for a scroll-near prefetch.
- **Index load** is the whole-resource lightweight read. Even at 200
  rows the p99 is 18ms; the index scales linearly with annotation
  count, which means a 5K-annotation book would still index in ~250ms.
  If/when we see a real book at that size, switching the index to a
  paginated read on demand is the next move.
- **PubSub broadcast** is essentially free with no subscribers — the
  hop is a single `:ets` insert. The number is the floor; real fan-out
  cost scales with the open-reader count.

## 4. Telemetry contract

All Slice 15.5 events are registered in `StudysyncWeb.Telemetry.metrics/0`
so any reporter (ConsoleReporter in dev, StatsD/Prometheus in prod) can
attach without code changes.

| Event                                          | Measurement | Tags                       | Where it fires |
| ---------------------------------------------- | ----------- | -------------------------- | -------------- |
| `[:studysync, :annotations, :create, :stop]`   | `:duration` | `type`, `outcome`          | `PdfLive.Show` `save_annotation` (`:telemetry.span/3` around the Ash action) |
| `[:studysync, :pubsub, :broadcast, :stop]`     | `:duration` | `event`, `topic`           | Each `broadcast_*` helper in `Annotations.PubSub`, `Activity.PubSub`, `Progress.PubSub` |
| `[:studysync, :ai, :answer, :stop]`            | `:duration` | `outcome`                  | Stub for Slice 11. Fires once `Studysync.AI.AnswerWorker` lands. |
| `[:phoenix, :live_view, :handle_event, :stop]` | `:duration` | `view`, `event`            | Phoenix.LiveView (built-in)                                                   |
| `[:phoenix, :live_view, :mount, :stop]`        | `:duration` | `view`                     | Phoenix.LiveView (built-in)                                                   |

`Studysync.Telemetry.DevLogger` attaches a `Logger.debug/1` handler in
`:dev` only (gated by `:dev_telemetry_logger?` in `config/dev.exs`). It
fires when an event exceeds its threshold:

- `phoenix.live_view.handle_event` > 50ms
- `phoenix.live_view.mount` > 200ms
- `studysync.annotations.create` > 75ms
- `studysync.pubsub.broadcast` > 25ms

These thresholds are deliberately quiet under steady-state load, so when
something *does* log it's a real signal worth investigating.

## 5. Open notes for follow-up

- **Subscriber count on PubSub broadcast** is not exposed by
  `Phoenix.PubSub`. If we need fan-out cardinality (e.g. for capacity
  planning at scale), wrap our own subscribe helpers and track counts
  alongside.
- **AI answer telemetry** is registered in metrics but has no producer
  yet. Slice 11 will wire it into the Oban worker.
- **Re-rendering on PubSub bursts** (10+ peers commenting at once)
  hasn't been load-tested. Stream inserts coalesce well in theory; if
  real-world reports a jank, the natural lever is a debounce on the
  workspace activity rail rather than the per-resource reader.
