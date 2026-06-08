<script>
  import { onMount, onDestroy } from "svelte";
  import * as pdfjsLib from "pdfjs-dist";
  import workerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";
  import { useLiveSvelte, useLiveEvent } from "live_svelte";

  pdfjsLib.GlobalWorkerOptions.workerSrc = workerUrl;

  // ---- Contract (CLAUDE.md §4.3) ----
  // Props from LiveView:
  //   file_url             : string  — auth-gated URL the canvas fetches the PDF from
  //   total_pages          : number  — page count from the persisted resource
  //   annotations          : array   — [{ id, number, page, rect: { x, y, width, height }, type }]
  //                                     rect coordinates are 0..1 normalized to the page
  //                                     type ∈ "comment" | "question" | "puzzle" | "ai_response"
  //   milestone_markers    : array   — [{ id, page, position: { x, y }, label }]
  //                                     position is 0..1 normalized to the page
  //   is_admin?            : bool    — actor is an admin of the workspace; surfaces
  //                                    the "+ Place milestone" option in the
  //                                    floating selection menu.
  //   rubber_stamps        : array   — [{ id, milestone_id, user_id, email }]
  //                                     drives the "X / N readers" + avatar
  //                                     cluster on the milestone popover and the
  //                                     "have I stamped?" check.
  //   current_user_id      : string  — actor id; compared against rubber_stamps[].user_id
  //   total_readers        : number  — workspace member count, denominator for X/N
  //   active_annotation_id : string  — id of the focused annotation; drives marker
  //                                     highlight and scroll-to-page on change
  //
  // Events to LiveView:
  //   text_selected      → { text, page, rect, type } when the user picks one of
  //                        the floating menu options. `type` ∈ "comment" |
  //                        "question" | "puzzle" | "milestone". The milestone
  //                        type is only emitted when `is_admin?` is true; the
  //                        LV opens a margin label form (defaulting the label
  //                        to the selected text) and creates the milestone on
  //                        submit using the selection's rect for position.
  //   annotation_clicked → { id } when the user clicks a marker in the prose
  //   apply_stamp        → { milestone_id } when the user confirms a stamp from
  //                        the milestone popover.
  //   pages_visible      → { first, last, primary } emitted (debounced)
  //                        whenever the set of pages intersecting the viewport
  //                        changes. `first`/`last` reflect the IO range
  //                        (with rootMargin); `primary` is the page with the
  //                        largest visual overlap against the actual viewport.
  //                        The LV uses `primary` as the focal page so the
  //                        margin column highlight + Page-scope tab match
  //                        what the reader is actually looking at.
  //                        (added Slice 15; revised Slice 15a; `primary`
  //                        added when scope tabs landed.)
  //   outline_loaded     → { chapters: [{ label, page }] } emitted once after
  //                        the PDF document loads, with top-level outline
  //                        entries flattened to label/page pairs. Empty list
  //                        when the PDF has no outline. The LV stores it as
  //                        @chapters and feeds the chapter rail.
  //
  // Server-pushed events (LiveView → canvas), consumed via useLiveEvent:
  //   scroll_to_page     → { page } — bring `page` into view (smooth). Used
  //                        by the chapter rail click; the IO callback then
  //                        updates :focal_page via pages_visible naturally.
  let {
    file_url,
    total_pages = 0,
    annotations = [],        // [{ id, number, page, rect, type, text }]
    milestone_markers = [],
    is_admin = false,
    rubber_stamps = [],
    current_user_id = null,
    total_readers = 0,
    active_annotation_id = null,
    page_readers = [],       // [{ page, count, emails }] — other readers' positions
    export_url = null,       // URL for the journal PDF download
  } = $props();

  const { pushEvent } = useLiveSvelte();

  // Server → canvas: bring a specific page into view (chapter rail click).
  // The IO callback then reports the new range via `pages_visible`, which
  // updates `:focal_page` — so we don't sync any state here, just scroll.
  useLiveEvent("scroll_to_page", (payload) => {
    const page = Number(payload?.page);
    if (!Number.isFinite(page)) return;
    scrollToPage(page);
  });

  let scrollEl = $state(null);
  let pages = $state([]);
  let currentPage = $state(1);
  let loadError = $state(null);
  // User-facing zoom percentage. 100 = comfortable reading default.
  let zoomPct = $state(100);
  let firstPageSize = $state(null);
  // Floating selection menu — { x, y, text, page, rect } or null.
  let selectionMenu = $state(null);
  // Local (client-only) yellow highlights — [{ id, page, rect }]. Not persisted.
  let localHighlights = $state([]);
  // Milestone popover — { x, y, milestone_id } or null. Anchored next to the
  // marker the user clicked; shows X/N readers + avatar cluster + stamp button.
  let milestonePopover = $state(null);
  // Hover-linking state — set by document-level "studysync:annotation-hover"
  // events dispatched from the margin column. Pure client-side; no LV roundtrip.
  let hoveredAnnotationId = $state(null);
  // Marker that should briefly pulse — cleared after the animation completes.
  let pulseAnnotationId = $state(null);
  // Milestone that was just stamped — shows a brief "Stamped!" confirmation
  // in the popover before closing it.
  let stampConfirmedMilestoneId = $state(null);

  // Reading quality: column width and view mode
  let widthMode = $state("medium"); // "narrow" | "medium" | "wide"
  let viewMode = $state("default"); // "default" | "sepia" | "night"

  // Navigation: thumbnail strip and chapter breadcrumb
  let showThumbs = $state(false);
  let localChapters = $state([]); // chapters received from outline_loaded, cached here too


  // Feature: in-document search + annotation note search
  let showSearch = $state(false);
  let searchQuery = $state("");
  let searchMode = $state("doc"); // "doc" | "notes"
  let searchResults = $state([]); // doc mode: [{ page, highlights: [{x,y,width,height}] }]
  let searchResultIndex = $state(0);
  let annotationMatchIndex = $state(0); // notes mode index
  let isSearching = $state(false);
  let searchInputEl = $state(null);

  // Polish: scroll-snap page transitions (toggleable)
  let snapMode = $state(false);
  // Polish: keyboard shortcut cheatsheet modal
  let showShortcuts = $state(false);

  // Reading timer — tracks active reading time, resets on 90s inactivity.
  let readingSeconds = $state(0);
  let _readingActive = false; // non-reactive internal flag
  let _readingInterval = null;
  let _inactivityTimeout = null;

  let pdfDoc = null;
  let observer = null;
  let pulseTimer = null;
  let stampConfirmTimer = null;
  // Text content cache for search — not reactive, cleared when pdfDoc changes.
  const pageTextCache = new Map();
  // Thumbnail render cache — separate from the main page render cache since
  // thumbs use a different scale. Cleared when the thumb panel reopens.
  const renderedThumbs = new Set();
  let thumbObserver = null;
  // Position persistence: restored once after pages load.
  let positionRestored = false;
  // Render-cache for canvases. Off $state so we don't trigger Svelte
  // re-renders on every page paint.
  const renderedPages = new Set();
  // Slice 15.1/15.2 — track which pages intersect the viewport (incl.
  // 1000px rootMargin) and report the range to LV so it can lazy-hydrate
  // annotation bodies for the matching pages. Debounced to coalesce rapid
  // scroll bursts into a single LV round-trip.
  const visiblePages = new Set();
  let visiblePagesDebounce = null;
  let lastReportedRange = null;

  // Internal PDF.js scale at user zoom = 100%. Tuned for retina readability.
  const BASE_INTERNAL_SCALE = 1.75;

  const internalScale = $derived((zoomPct / 100) * BASE_INTERNAL_SCALE);

  const pageDisplayWidth = $derived(
    (firstPageSize ? firstPageSize.width : 612) * internalScale,
  );
  const pageDisplayHeight = $derived(
    (firstPageSize ? firstPageSize.height : 792) * internalScale,
  );

  const annotationsByPage = $derived.by(() => {
    const map = new Map();
    for (const a of annotations || []) {
      const list = map.get(a.page) || [];
      list.push(a);
      map.set(a.page, list);
    }
    return map;
  });

  const milestonesByPage = $derived.by(() => {
    const map = new Map();
    for (const m of milestone_markers || []) {
      const list = map.get(m.page) || [];
      list.push(m);
      map.set(m.page, list);
    }
    return map;
  });

  // Stamps grouped by milestone — drives the per-milestone popover counts and
  // avatar cluster (Slice 13). Recomputed only when the prop changes.
  const stampsByMilestone = $derived.by(() => {
    const map = new Map();
    for (const s of rubber_stamps || []) {
      const list = map.get(s.milestone_id) || [];
      list.push(s);
      map.set(s.milestone_id, list);
    }
    return map;
  });

  const popoverContext = $derived.by(() => {
    if (!milestonePopover) return null;
    const milestone = (milestone_markers || []).find(
      (m) => m.id === milestonePopover.milestone_id,
    );
    if (!milestone) return null;
    const stamps = stampsByMilestone.get(milestone.id) || [];
    const stampedByMe =
      current_user_id != null &&
      stamps.some((s) => s.user_id === current_user_id);
    return { milestone, stamps, stampedByMe };
  });

  // Current chapter based on focal page — last chapter whose start page ≤ currentPage.
  const currentChapter = $derived.by(() => {
    if (!localChapters.length) return null;
    const sorted = [...localChapters].sort((a, b) => a.page - b.page);
    let result = null;
    for (const c of sorted) {
      if (c.page <= currentPage) result = c;
      else break;
    }
    return result;
  });

  // Annotation note search — filters annotations whose selected text matches.
  const annotationMatches = $derived.by(() => {
    if (searchMode !== "notes" || !searchQuery.trim()) return [];
    const lower = searchQuery.toLowerCase();
    return (annotations || []).filter(
      (a) => (a.text || "").toLowerCase().includes(lower),
    );
  });

  // Page readers keyed by page number for the presence badge lookup.
  const pageReadersMap = $derived.by(() => {
    const map = new Map();
    for (const r of page_readers || []) map.set(r.page, r);
    return map;
  });

  // Reading time label — null until the user has been reading for 60+ seconds.
  const readingTimeLabel = $derived.by(() => {
    if (readingSeconds < 60) return null;
    const m = Math.floor(readingSeconds / 60);
    const h = Math.floor(m / 60);
    return h > 0 ? `${h}h ${m % 60}m` : `${m}m`;
  });

  // Search highlights keyed by page for fast lookup in the highlight layer.
  const searchHighlightsByPage = $derived.by(() => {
    const map = new Map();
    for (const r of searchResults) map.set(r.page, r.highlights);
    return map;
  });

  // Total match count across all result pages.
  const totalSearchHits = $derived(
    searchResults.reduce((sum, r) => sum + r.highlights.length, 0),
  );

  // Annotations sorted in reading order (page → top-to-bottom) for [ / ] navigation.
  const sortedAnnotations = $derived.by(() =>
    [...(annotations || [])].sort((a, b) => {
      if (a.page !== b.page) return a.page - b.page;
      return (a.rect?.y ?? 0) - (b.rect?.y ?? 0);
    }),
  );

  // Heatmap viewport indicator — rough position of current page in the document.
  const heatmapViewportTop = $derived(
    pages.length > 1 ? ((currentPage - 1) / (pages.length - 1)) * 100 : 0,
  );

  const ZOOM_STEPS = [75, 100, 125, 150, 175, 200];
  const ZOOM_MIN = 50;
  const ZOOM_MAX = 300;

  onMount(async () => {
    if (!file_url) return;

    try {
      pdfDoc = await pdfjsLib.getDocument({ url: file_url }).promise;

      const first = await pdfDoc.getPage(1);
      const fv = first.getViewport({ scale: 1 });
      firstPageSize = { width: fv.width, height: fv.height };

      pages = Array.from({ length: pdfDoc.numPages }, (_, i) => ({
        pageNum: i + 1,
        container: null,
        canvas: null,
        textLayer: null,
        thumbContainer: null,
        thumbCanvas: null,
      }));

      reportOutline();
    } catch (e) {
      console.error("PdfCanvasRenderer: failed to load PDF", e);
      loadError = e?.message || "Failed to load PDF";
    }
  });

  // Pull the PDF's top-level outline (table of contents) and ship it to LV
  // as { chapters: [{ label, page }] }. Resolves each item's destination to a
  // 1-indexed page number; items we can't resolve are skipped silently.
  // Nested children are ignored on purpose — the rail is a quiet 40px column
  // and a flat top-level list is what fits the visual.
  async function reportOutline() {
    if (!pdfDoc) return;
    let chapters = [];
    try {
      const outline = await pdfDoc.getOutline?.();
      if (Array.isArray(outline) && outline.length > 0) {
        for (const item of outline) {
          const page = await resolveOutlinePage(item);
          if (page == null) continue;
          const label = (item.title || "").trim();
          if (!label) continue;
          chapters.push({ label, page });
        }
      }
    } catch (e) {
      console.warn("PdfCanvasRenderer: outline extraction failed", e);
    }
    localChapters = chapters;
    pushEvent("outline_loaded", { chapters });
  }

  async function resolveOutlinePage(item) {
    try {
      let dest = item.dest;
      if (typeof dest === "string") {
        dest = await pdfDoc.getDestination(dest);
      }
      if (!Array.isArray(dest) || dest.length === 0) return null;
      const ref = dest[0];
      if (!ref || typeof ref !== "object") return null;
      const pageIndex = await pdfDoc.getPageIndex(ref);
      if (typeof pageIndex !== "number" || pageIndex < 0) return null;
      return pageIndex + 1;
    } catch {
      return null;
    }
  }

  onDestroy(() => {
    if (observer) observer.disconnect();
    if (thumbObserver) thumbObserver.disconnect();
    if (pdfDoc) pdfDoc.destroy?.();
    if (pulseTimer) clearTimeout(pulseTimer);
    if (stampConfirmTimer) clearTimeout(stampConfirmTimer);
    if (visiblePagesDebounce) clearTimeout(visiblePagesDebounce);
    pageTextCache.clear();
    renderedThumbs.clear();
  });

  // Hover linking: the margin column dispatches a custom DOM event when a
  // margin note is hovered. Listening on document avoids a server round-trip
  // for what is purely a visual cross-pane effect.
  $effect(() => {
    const handler = (e) => {
      hoveredAnnotationId = e.detail?.id ?? null;
    };
    document.addEventListener("studysync:annotation-hover", handler);
    return () =>
      document.removeEventListener("studysync:annotation-hover", handler);
  });

  // Auto-focus the search input whenever the search bar opens.
  $effect(() => {
    if (showSearch && searchInputEl) searchInputEl.focus();
  });

  // Reading timer: track activity via document events, increment every second
  // while active, reset the clock after 90s of inactivity.
  $effect(() => {
    function markActivity() {
      if (!_readingActive) {
        _readingActive = true;
        _readingInterval = setInterval(() => { readingSeconds += 1; }, 1000);
      }
      if (_inactivityTimeout) clearTimeout(_inactivityTimeout);
      _inactivityTimeout = setTimeout(() => {
        _readingActive = false;
        if (_readingInterval) { clearInterval(_readingInterval); _readingInterval = null; }
      }, 90_000);
    }

    const events = ["mousemove", "scroll", "keydown", "click", "touchstart"];
    events.forEach((ev) => document.addEventListener(ev, markActivity, { passive: true }));

    return () => {
      events.forEach((ev) => document.removeEventListener(ev, markActivity));
      if (_readingInterval) clearInterval(_readingInterval);
      if (_inactivityTimeout) clearTimeout(_inactivityTimeout);
    };
  });

  // Reset annotation match index whenever query or mode changes.
  $effect(() => {
    searchQuery; searchMode; // track both as dependencies
    annotationMatchIndex = 0;
  });

  // Debounced search: re-runs whenever searchQuery changes.
  $effect(() => {
    const q = searchQuery;
    const timer = setTimeout(() => runSearch(q), 300);
    return () => clearTimeout(timer);
  });

  // Thumbnail strip: lazy-render thumbs via their own IntersectionObserver.
  // Re-runs when showThumbs toggles; clearing renderedThumbs ensures canvases
  // that were destroyed and re-created on re-open get repainted.
  $effect(() => {
    if (!showThumbs || pages.length === 0 || !pdfDoc) {
      if (thumbObserver) { thumbObserver.disconnect(); thumbObserver = null; }
      return;
    }

    renderedThumbs.clear();

    thumbObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const num = Number(entry.target.dataset.thumbNum);
          if (!renderedThumbs.has(num)) renderThumb(num);
        }
      },
      { threshold: 0 },
    );

    for (const p of pages) {
      if (p.thumbContainer) thumbObserver.observe(p.thumbContainer);
    }

    return () => { if (thumbObserver) { thumbObserver.disconnect(); thumbObserver = null; } };
  });

  // Position persistence: restore saved page once after the pages array is populated.
  $effect(() => {
    if (positionRestored || pages.length === 0 || !file_url) return;
    positionRestored = true;
    const key = posKey();
    if (!key) return;
    const saved = parseInt(localStorage.getItem(key) || "0", 10);
    if (saved > 1 && saved <= pages.length) {
      // Delay to ensure page containers are bound by Svelte's DOM update.
      setTimeout(() => scrollToPage(saved), 150);
    }
  });

  // Position persistence: save current page whenever it changes.
  $effect(() => {
    const page = currentPage;
    if (!file_url || pages.length === 0) return;
    const key = posKey();
    if (!key) return;
    if (page > 1) {
      localStorage.setItem(key, String(page));
    } else {
      localStorage.removeItem(key);
    }
  });

  // Scroll-to-page-and-highlight when active_annotation_id changes (5.3, 5.6).
  $effect(() => {
    const id = active_annotation_id;
    if (!id || !scrollEl) return;

    const target = (annotations || []).find((a) => a.id === id);
    if (!target) return;

    const slot = pages[target.page - 1];
    if (slot?.container) {
      slot.container.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    pulseAnnotationId = id;
    if (pulseTimer) clearTimeout(pulseTimer);
    pulseTimer = setTimeout(() => {
      pulseAnnotationId = null;
    }, 1400);
  });

  // CLAUDE.md §6: virtualization — only render pages near the viewport.
  $effect(() => {
    if (!scrollEl || pages.length === 0 || !pdfDoc) return;

    if (observer) observer.disconnect();

    observer = new IntersectionObserver(
      (entries) => {
        let changed = false;
        for (const entry of entries) {
          const num = Number(entry.target.dataset.pageNum);
          if (entry.isIntersecting) {
            currentPage = num;
            if (!renderedPages.has(num)) {
              renderPage(num);
            }
            if (!visiblePages.has(num)) {
              visiblePages.add(num);
              changed = true;
            }
          } else if (visiblePages.delete(num)) {
            changed = true;
          }
        }
        if (changed) scheduleVisiblePagesReport();
      },
      { root: scrollEl, rootMargin: "1000px 0px", threshold: 0 },
    );

    for (const p of pages) {
      if (p.container) observer.observe(p.container);
    }
  });

  // When zoom changes, invalidate the render cache and re-paint pages
  // currently in (or near) the viewport.
  $effect(() => {
    const _ = internalScale;
    if (!pdfDoc || pages.length === 0 || !scrollEl) return;

    renderedPages.clear();

    const root = scrollEl.getBoundingClientRect();
    for (const p of pages) {
      if (!p.container) continue;
      const r = p.container.getBoundingClientRect();
      if (r.bottom > root.top - 500 && r.top < root.bottom + 500) {
        renderPage(p.pageNum);
      }
    }
  });

  // Cmd / Ctrl + wheel → zoom inside the canvas.
  $effect(() => {
    if (!scrollEl) return;

    const onWheel = (e) => {
      if (!(e.ctrlKey || e.metaKey)) return;
      e.preventDefault();
      const step = e.deltaY < 0 ? 10 : -10;
      zoomPct = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, zoomPct + step));
    };

    scrollEl.addEventListener("wheel", onWheel, { passive: false });
    return () => scrollEl.removeEventListener("wheel", onWheel);
  });

  // Slice 16.6 — keyboard shortcuts. Document-level so the user doesn't
  // need to focus the canvas first; we early-out when the focus is in an
  // input/textarea so typing into a reply form or the milestone label
  // input doesn't accidentally page-nav.
  //
  //   J / ArrowDown → next page (smooth scroll)
  //   K / ArrowUp   → previous page
  //   N             → "Add comment" on the current selection (if any)
  //   Escape        → close selection menu / milestone popover. (Forms
  //                   in the margin column are closed by the LV via its
  //                   own phx-window-keydown handler, since the form DOM
  //                   doesn't live in this component.)
  $effect(() => {
    if (!scrollEl) return;

    const onKey = (e) => {
      const tag = e.target?.tagName;
      const editable =
        tag === "INPUT" ||
        tag === "TEXTAREA" ||
        e.target?.isContentEditable;

      // Cmd/Ctrl+F — always open search, even from editable fields.
      if ((e.metaKey || e.ctrlKey) && e.key === "f") {
        e.preventDefault();
        showSearch ? closeSearch() : openSearch();
        return;
      }

      if (e.key === "Escape") {
        let consumed = false;
        if (showShortcuts) { showShortcuts = false; consumed = true; }
        if (showSearch) { closeSearch(); consumed = true; }
        if (milestonePopover) { closeMilestonePopover(); consumed = true; }
        if (selectionMenu) {
          selectionMenu = null;
          window.getSelection()?.removeAllRanges();
          consumed = true;
        }
        if (consumed) e.preventDefault();
        return;
      }

      if (editable) return;
      if (e.metaKey || e.ctrlKey || e.altKey) return;

      // ? — keyboard shortcut cheatsheet
      if (e.key === "?") { e.preventDefault(); showShortcuts = !showShortcuts; return; }

      // Selection menu: pick annotation type by letter.
      if (selectionMenu) {
        if (e.key === "h" || e.key === "H") { e.preventDefault(); commitHighlight(null); return; }
        if (e.key === "c" || e.key === "C") { e.preventDefault(); commitSelection(null, "comment"); return; }
        if (e.key === "q" || e.key === "Q") { e.preventDefault(); commitSelection(null, "question"); return; }
        if (e.key === "p" || e.key === "P") { e.preventDefault(); commitSelection(null, "puzzle"); return; }
        if (e.key === "a" || e.key === "A") { e.preventDefault(); commitSelection(null, "ai"); return; }
        if (is_admin && (e.key === "m" || e.key === "M")) { e.preventDefault(); commitSelection(null, "milestone"); return; }
      }

      // [ / ] — navigate between annotation markers in reading order.
      if (e.key === "]") { e.preventDefault(); navigateAnnotation(1); }
      else if (e.key === "[") { e.preventDefault(); navigateAnnotation(-1); }

      // J / K — page navigation (unchanged).
      else if (e.key === "j" || e.key === "ArrowDown") {
        e.preventDefault();
        scrollByPage(1);
      } else if (e.key === "k" || e.key === "ArrowUp") {
        e.preventDefault();
        scrollByPage(-1);
      }

      // Keyboard zoom: + / = zoom in, - zoom out, 0 reset to 100%.
      else if (e.key === "+" || e.key === "=") { e.preventDefault(); zoomIn(); }
      else if (e.key === "-") { e.preventDefault(); zoomOut(); }
      else if (e.key === "0") { e.preventDefault(); zoomPct = 100; }
    };

    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  });

  function scrollByPage(direction) {
    if (!scrollEl) return;
    const total = pages.length;
    if (total === 0) return;
    const next = Math.min(total, Math.max(1, currentPage + direction));
    if (next === currentPage) return;
    const slot = pages[next - 1];
    if (slot?.container) {
      slot.container.scrollIntoView({ behavior: "smooth", block: "start" });
      currentPage = next;
    }
  }

  function scrollToPage(page) {
    if (!scrollEl) return;
    const total = pages.length;
    if (total === 0) return;
    const target = Math.min(total, Math.max(1, Math.trunc(page)));
    const slot = pages[target - 1];
    if (slot?.container) {
      slot.container.scrollIntoView({ behavior: "smooth", block: "start" });
      currentPage = target;
    }
  }

  // Watch the document's selection so we can show the floating "Add Comment"
  // button whenever the user has a non-empty selection inside one of our pages.
  // Debounced 350ms so the menu only appears after the user finishes selecting.
  $effect(() => {
    if (!scrollEl) return;

    let debounceTimer = null;

    const handler = () => {
      clearTimeout(debounceTimer);

      const sel = window.getSelection();
      if (!sel || sel.rangeCount === 0 || sel.toString().trim() === "") {
        selectionMenu = null;
        return;
      }

      debounceTimer = setTimeout(() => {
        const sel2 = window.getSelection();
        if (!sel2 || sel2.rangeCount === 0) {
          selectionMenu = null;
          return;
        }

        const text = sel2.toString();
        if (text.trim() === "") {
          selectionMenu = null;
          return;
        }

        const range = sel2.getRangeAt(0);
        const anchor =
          range.startContainer.nodeType === Node.TEXT_NODE
            ? range.startContainer.parentElement
            : range.startContainer;
        const pageEl = anchor?.closest?.("[data-page-num]");
        if (!pageEl || !scrollEl.contains(pageEl)) {
          selectionMenu = null;
          return;
        }

        const rangeRect = range.getBoundingClientRect();
        if (rangeRect.width === 0 || rangeRect.height === 0) {
          selectionMenu = null;
          return;
        }

        const pageRect = pageEl.getBoundingClientRect();

        selectionMenu = {
          // Position fixed against the viewport so the menu floats with the
          // selection regardless of scroll position.
          x: rangeRect.right + 8,
          y: rangeRect.top,
          text,
          page: Number(pageEl.dataset.pageNum),
          rect: {
            x: (rangeRect.left - pageRect.left) / pageRect.width,
            y: (rangeRect.top - pageRect.top) / pageRect.height,
            width: rangeRect.width / pageRect.width,
            height: rangeRect.height / pageRect.height,
          },
        };
      }, 350);
    };

    document.addEventListener("selectionchange", handler);
    return () => {
      document.removeEventListener("selectionchange", handler);
      clearTimeout(debounceTimer);
    };
  });

  // Slice 15.1/15.2 — push the current visible-page range to LV.
  // Debounced (120ms) so a fast scroll doesn't fire on every IO callback;
  // and de-duped so we don't ship the same range twice in a row.
  //
  // `first`/`last` come from `visiblePages`, which is populated by an
  // IntersectionObserver with a 1000px rootMargin — i.e. it includes
  // pages just above/below the actual viewport so they can pre-render.
  // That set is too generous to answer "what page is the reader looking
  // at?" — `first` can be a page mostly above the viewport. So we also
  // compute a `primary` page (the one with the largest visual overlap
  // against the *true* viewport) and ship it as a third field. The LV
  // uses `primary` as the focal page; `first`/`last` retain their
  // virtualization-range meaning.
  function scheduleVisiblePagesReport() {
    if (visiblePagesDebounce) clearTimeout(visiblePagesDebounce);
    visiblePagesDebounce = setTimeout(() => {
      visiblePagesDebounce = null;
      if (visiblePages.size === 0) return;
      let first = Infinity;
      let last = -Infinity;
      for (const p of visiblePages) {
        if (p < first) first = p;
        if (p > last) last = p;
      }

      const primary = computePrimaryPage(first);

      if (
        lastReportedRange &&
        lastReportedRange.first === first &&
        lastReportedRange.last === last &&
        lastReportedRange.primary === primary
      ) {
        return;
      }
      lastReportedRange = { first, last, primary };
      pushEvent("pages_visible", { first, last, primary });
    }, 120);
  }

  // Pick the page whose container has the largest visible overlap with
  // the scroll container's true viewport. Falls back to `first` when no
  // candidate has any visible overlap (rare — happens during teardown
  // before `pages` is populated).
  function computePrimaryPage(first) {
    if (!scrollEl) return first;
    const root = scrollEl.getBoundingClientRect();
    let bestPage = null;
    let bestOverlap = 0;

    for (const p of visiblePages) {
      const slot = pages[p - 1];
      if (!slot?.container) continue;
      const r = slot.container.getBoundingClientRect();
      const overlap = Math.max(
        0,
        Math.min(r.bottom, root.bottom) - Math.max(r.top, root.top),
      );
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        bestPage = p;
      }
    }

    return bestPage ?? first;
  }

  async function renderPage(num) {
    if (renderedPages.has(num)) return;
    renderedPages.add(num);

    const slot = pages[num - 1];
    if (!slot?.canvas) {
      renderedPages.delete(num);
      return;
    }

    try {
      const dpr = window.devicePixelRatio || 1;
      const page = await pdfDoc.getPage(num);

      const renderViewport = page.getViewport({ scale: internalScale * dpr });
      const displayViewport = page.getViewport({ scale: internalScale });

      const canvas = slot.canvas;
      const ctx = canvas.getContext("2d");
      canvas.width = renderViewport.width;
      canvas.height = renderViewport.height;
      canvas.style.width = `${displayViewport.width}px`;
      canvas.style.height = `${displayViewport.height}px`;

      await page.render({ canvasContext: ctx, viewport: renderViewport })
        .promise;

      // Render the text layer on top of the canvas. PDF.js's TextLayer
      // creates positioned, transparent <span>s that the browser's native
      // selection picks up — that's how we get text selection working.
      if (slot.textLayer) {
        const textContent = await page.getTextContent();
        slot.textLayer.replaceChildren();
        slot.textLayer.style.setProperty(
          "--scale-factor",
          String(displayViewport.scale),
        );
        const textLayer = new pdfjsLib.TextLayer({
          textContentSource: textContent,
          container: slot.textLayer,
          viewport: displayViewport,
        });
        await textLayer.render();
      }
    } catch (e) {
      console.error(`PdfCanvasRenderer: render failed on page ${num}`, e);
      renderedPages.delete(num);
    }
  }

  function onMarkerClick(e, id) {
    e.preventDefault();
    e.stopPropagation();
    pushEvent("annotation_clicked", { id });
  }

  // Slice 16.3 — hover-linking, PDF → margin direction. The margin column
  // dispatches the same event when a card is hovered; emitting it here
  // lets the MarginColumn JS hook dim non-matching cards and the canvas
  // dim non-matching markers (via the `hoveredAnnotationId` state, which
  // also listens on document for the same event). One DOM event, both
  // directions, no LV round-trip.
  function dispatchMarkerHover(id) {
    document.dispatchEvent(
      new CustomEvent("studysync:annotation-hover", { detail: { id } }),
    );
  }

  // Click a milestone marker → open the popover anchored to the marker.
  // Coordinates are viewport-fixed so the popover stays put while the user
  // skims the popover content; closing on outside click resets state.
  function onMilestoneMarkerClick(e, milestone_id) {
    e.preventDefault();
    e.stopPropagation();

    const rect = e.currentTarget.getBoundingClientRect();

    milestonePopover = {
      x: rect.right + 8,
      y: rect.top,
      milestone_id,
    };
  }

  function closeMilestonePopover() {
    milestonePopover = null;
  }

  function confirmStamp(e) {
    e?.preventDefault?.();
    if (!popoverContext || popoverContext.stampedByMe) return;
    const mid = popoverContext.milestone.id;
    pushEvent("apply_stamp", { milestone_id: mid });
    // Show a brief "Stamped!" confirmation in the popover, then close it.
    stampConfirmedMilestoneId = mid;
    if (stampConfirmTimer) clearTimeout(stampConfirmTimer);
    stampConfirmTimer = setTimeout(() => {
      stampConfirmedMilestoneId = null;
      milestonePopover = null;
    }, 700);
  }

  // Close the popover on Escape or when the user clicks outside it.
  $effect(() => {
    if (!milestonePopover) return;

    const onKey = (e) => {
      if (e.key === "Escape") closeMilestonePopover();
    };
    const onDocClick = (e) => {
      const popoverEl = document.querySelector(".milestone-popover");
      const markerEl = document.querySelector(
        `[data-milestone-id="${milestonePopover.milestone_id}"]`,
      );
      if (popoverEl?.contains(e.target)) return;
      if (markerEl?.contains(e.target)) return;
      closeMilestonePopover();
    };

    document.addEventListener("keydown", onKey);
    document.addEventListener("mousedown", onDocClick);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("mousedown", onDocClick);
    };
  });

  function emailInitials(email) {
    if (!email) return "·";
    const local = String(email).split("@")[0] || "";
    return local.slice(0, 2).toUpperCase();
  }

  function commitSelection(e, type) {
    // mousedown's preventDefault keeps focus on the page so the window
    // selection isn't cleared before our handler runs.
    e?.preventDefault?.();
    if (!selectionMenu) return;

    pushEvent("text_selected", {
      text: selectionMenu.text,
      page: selectionMenu.page,
      rect: selectionMenu.rect,
      type,
    });

    window.getSelection()?.removeAllRanges();
    selectionMenu = null;
  }

  function commitHighlight(e) {
    e?.preventDefault?.();
    if (!selectionMenu) return;

    localHighlights = [
      ...localHighlights,
      { id: crypto.randomUUID(), page: selectionMenu.page, rect: selectionMenu.rect },
    ];

    window.getSelection()?.removeAllRanges();
    selectionMenu = null;
  }

  function zoomIn() {
    const next = ZOOM_STEPS.find((s) => s > zoomPct);
    zoomPct = next ?? Math.min(ZOOM_MAX, zoomPct + 25);
  }

  function zoomOut() {
    for (let i = ZOOM_STEPS.length - 1; i >= 0; i--) {
      if (ZOOM_STEPS[i] < zoomPct) {
        zoomPct = ZOOM_STEPS[i];
        return;
      }
    }
    zoomPct = Math.max(ZOOM_MIN, zoomPct - 25);
  }

  // ── Navigation ───────────────────────────────────────────────────────────────

  function posKey() {
    if (!file_url) return null;
    try {
      return `studysync:pos:${new URL(file_url).pathname}`;
    } catch {
      return `studysync:pos:${file_url.split("?")[0]}`;
    }
  }

  async function renderThumb(num) {
    if (renderedThumbs.has(num)) return;
    renderedThumbs.add(num);
    const slot = pages[num - 1];
    if (!slot?.thumbCanvas) { renderedThumbs.delete(num); return; }

    try {
      const page = await pdfDoc.getPage(num);
      // Scale so the thumb fits in an 80px wide column.
      const nativeW = firstPageSize?.width ?? 612;
      const scale = 80 / nativeW;
      const vp = page.getViewport({ scale });
      const canvas = slot.thumbCanvas;
      const ctx = canvas.getContext("2d");
      canvas.width = vp.width;
      canvas.height = vp.height;
      await page.render({ canvasContext: ctx, viewport: vp }).promise;
    } catch {
      renderedThumbs.delete(num);
    }
  }

  // ── Reading quality ──────────────────────────────────────────────────────────

  const WIDTH_MODES = ["narrow", "medium", "wide"];
  const VIEW_MODES = ["default", "sepia", "night"];

  function cycleWidth() {
    const idx = WIDTH_MODES.indexOf(widthMode);
    widthMode = WIDTH_MODES[(idx + 1) % WIDTH_MODES.length];
  }

  function cycleViewMode() {
    const idx = VIEW_MODES.indexOf(viewMode);
    viewMode = VIEW_MODES[(idx + 1) % VIEW_MODES.length];
  }

  // ── Search ──────────────────────────────────────────────────────────────────

  function openSearch() {
    showSearch = true;
  }

  function closeSearch() {
    showSearch = false;
    searchQuery = "";
    searchResults = [];
    searchResultIndex = 0;
  }

  async function runSearch(query) {
    if (!query.trim() || !pdfDoc) {
      searchResults = [];
      searchResultIndex = 0;
      return;
    }
    isSearching = true;
    const lower = query.toLowerCase();
    const results = [];

    for (let pageNum = 1; pageNum <= pdfDoc.numPages; pageNum++) {
      let cached = pageTextCache.get(pageNum);
      if (!cached) {
        try {
          const page = await pdfDoc.getPage(pageNum);
          const vp = page.getViewport({ scale: 1 });
          const tc = await page.getTextContent();
          cached = { items: tc.items, vw: vp.width, vh: vp.height };
          pageTextCache.set(pageNum, cached);
        } catch {
          continue;
        }
      }

      const { items, vw, vh } = cached;
      const highlights = [];

      for (const item of items) {
        if (!item.str || !item.str.toLowerCase().includes(lower)) continue;
        // item.transform = [scaleX, shearY, shearX, scaleY, tx, ty]
        // PDF y-axis is bottom-up; convert to top-down normalized coords.
        const tx = item.transform[4];
        const ty = item.transform[5];
        const h = item.height > 0 ? item.height : 12;
        const w = item.width > 0 ? item.width : 0;
        if (w === 0) continue;
        highlights.push({
          x: tx / vw,
          y: (vh - ty - h) / vh,
          width: w / vw,
          height: h / vh,
        });
      }

      if (highlights.length > 0) results.push({ page: pageNum, highlights });
    }

    searchResults = results;
    searchResultIndex = 0;
    isSearching = false;

    if (results.length > 0) scrollToPage(results[0].page);
  }

  function searchGoTo(idx) {
    if (searchMode === "notes") {
      if (annotationMatches.length === 0) return;
      annotationMatchIndex = ((idx % annotationMatches.length) + annotationMatches.length) % annotationMatches.length;
      const match = annotationMatches[annotationMatchIndex];
      if (match) pushEvent("annotation_clicked", { id: match.id });
    } else {
      if (searchResults.length === 0) return;
      searchResultIndex = ((idx % searchResults.length) + searchResults.length) % searchResults.length;
      scrollToPage(searchResults[searchResultIndex].page);
    }
  }

  // ── Annotation keyboard navigation ──────────────────────────────────────────

  function navigateAnnotation(direction) {
    if (sortedAnnotations.length === 0) return;
    const currentIdx = active_annotation_id
      ? sortedAnnotations.findIndex((a) => a.id === active_annotation_id)
      : -1;
    const nextIdx = Math.max(
      0,
      Math.min(sortedAnnotations.length - 1, currentIdx + direction),
    );
    const next = sortedAnnotations[nextIdx];
    if (next && next.id !== active_annotation_id) {
      pushEvent("annotation_clicked", { id: next.id });
    }
  }
</script>

<div
  class="reader"
  class:width-narrow={widthMode === "narrow"}
  class:width-wide={widthMode === "wide"}
  class:mode-sepia={viewMode === "sepia"}
  class:mode-night={viewMode === "night"}
  class:snap-mode={snapMode}
  data-testid="pdf-canvas-root"
>
  <header class="indicator">
    <button
      class="indicator-btn thumb-toggle"
      class:is-active={showThumbs}
      onclick={() => (showThumbs = !showThumbs)}
      aria-label="Toggle page thumbnails"
      title="Page thumbnails"
    >
      ≡
    </button>

    <span class="sep">·</span>

    <span class="num">{currentPage}</span>
    <span class="sep">/</span>
    <span class="num">{pages.length || total_pages}</span>

    {#if currentChapter}
      <span class="sep">·</span>
      <span class="chapter-crumb" title={currentChapter.label}>{currentChapter.label}</span>
    {/if}

    {#if readingTimeLabel}
      <span class="sep">·</span>
      <span class="reading-time" title="Active reading time this session">{readingTimeLabel}</span>
    {/if}

    <span class="spacer"></span>

    <button
      class="indicator-btn"
      onclick={cycleWidth}
      title="Column width: {widthMode} (click to cycle)"
      aria-label="Cycle reading width"
    >
      {widthMode === "narrow" ? "NRW" : widthMode === "wide" ? "WDE" : "MED"}
    </button>

    <span class="sep">·</span>

    <button
      class="indicator-btn"
      class:is-active={viewMode !== "default"}
      onclick={cycleViewMode}
      title="View mode: {viewMode} (click to cycle)"
      aria-label="Cycle view mode"
    >
      {viewMode === "sepia" ? "SEPIA" : viewMode === "night" ? "NIGHT" : "DEF"}
    </button>

    <span class="sep">·</span>

    <button
      class="search-toggle"
      class:is-active={showSearch}
      onclick={openSearch}
      aria-label="Search document (⌘F)"
      title="Search (⌘F)"
    >
      ⌕
    </button>

    <button
      class="zoom-btn"
      onclick={zoomOut}
      aria-label="Zoom out"
      title="Zoom out (−)"
      disabled={zoomPct <= ZOOM_MIN}
    >
      −
    </button>
    <span class="zoom-percent num">{zoomPct}%</span>
    <button
      class="zoom-btn"
      onclick={zoomIn}
      aria-label="Zoom in"
      title="Zoom in (+)"
      disabled={zoomPct >= ZOOM_MAX}
    >
      +
    </button>

    <span class="sep">·</span>

    <button
      class="indicator-btn"
      class:is-active={snapMode}
      onclick={() => (snapMode = !snapMode)}
      title="Snap page transitions (toggle)"
      aria-label="Toggle page snap"
    >
      SNAP
    </button>

    {#if export_url}
      <a
        href={export_url}
        download
        class="indicator-btn export-link"
        title="Download annotated journal PDF"
        aria-label="Export journal PDF"
      >
        ⇓
      </a>
    {/if}

    <button
      class="indicator-btn"
      onclick={() => (showShortcuts = !showShortcuts)}
      title="Keyboard shortcuts (?)"
      aria-label="Show keyboard shortcuts"
    >
      ?
    </button>
  </header>

  {#if showSearch}
    <div class="search-bar" role="search" aria-label="Search document">
      <span class="search-icon" aria-hidden="true">⌕</span>
      <input
        bind:this={searchInputEl}
        class="search-input"
        type="text"
        placeholder={searchMode === "doc" ? "Search text…" : "Search notes…"}
        bind:value={searchQuery}
        onkeydown={(e) => {
          if (e.key === "Escape") { closeSearch(); e.preventDefault(); }
          else if (e.key === "Enter") {
            e.preventDefault();
            const curIdx = searchMode === "doc" ? searchResultIndex : annotationMatchIndex;
            searchGoTo(e.shiftKey ? curIdx - 1 : curIdx + 1);
          }
        }}
        aria-label="Search term"
        autocomplete="off"
        spellcheck="false"
      />
      {#if isSearching && searchMode === "doc"}
        <span class="search-status num" aria-live="polite">…</span>
      {:else if searchQuery.trim()}
        <span class="search-status num" aria-live="polite">
          {#if searchMode === "doc"}
            {#if totalSearchHits === 0}no results{:else}{searchResultIndex + 1} / {searchResults.length}{/if}
          {:else}
            {#if annotationMatches.length === 0}no notes{:else}{annotationMatchIndex + 1} / {annotationMatches.length}{/if}
          {/if}
        </span>
      {/if}
      <button
        class="search-nav"
        onclick={() => searchGoTo(searchMode === "doc" ? searchResultIndex - 1 : annotationMatchIndex - 1)}
        disabled={searchMode === "doc" ? searchResults.length === 0 : annotationMatches.length === 0}
        aria-label="Previous match"
        title="Previous (Shift+Enter)"
      >↑</button>
      <button
        class="search-nav"
        onclick={() => searchGoTo(searchMode === "doc" ? searchResultIndex + 1 : annotationMatchIndex + 1)}
        disabled={searchMode === "doc" ? searchResults.length === 0 : annotationMatches.length === 0}
        aria-label="Next match"
        title="Next (Enter)"
      >↓</button>
      <span class="search-mode-tabs" role="group" aria-label="Search scope">
        <button
          class="search-mode-tab"
          class:is-active={searchMode === "doc"}
          onclick={() => (searchMode = "doc")}
        >Text</button>
        <button
          class="search-mode-tab"
          class:is-active={searchMode === "notes"}
          onclick={() => (searchMode = "notes")}
        >Notes</button>
      </span>
      <button class="search-close" onclick={closeSearch} aria-label="Close search">×</button>
    </div>
  {/if}

  <div class="reader-body">
    {#if showThumbs}
      <div class="thumb-panel">
        {#each pages as p (p.pageNum)}
          <button
            class="thumb-item"
            class:is-current={p.pageNum === currentPage}
            data-thumb-num={p.pageNum}
            bind:this={p.thumbContainer}
            onclick={() => scrollToPage(p.pageNum)}
            aria-label="Jump to page {p.pageNum}"
            title="Page {p.pageNum}"
          >
            <canvas bind:this={p.thumbCanvas}></canvas>
            <span class="thumb-num num">{p.pageNum}</span>
          </button>
        {/each}
      </div>
    {/if}

  <div class="scroll" bind:this={scrollEl}>
    {#if loadError}
      <p class="error">Couldn't load this PDF: {loadError}</p>
    {/if}

    <!-- Slice 16.5 — quiet loading skeleton while PDF.js fetches the
         document. Two empty page rectangles with a subtle shimmer give
         the user a stable layout to anchor their eye while the real
         pages stream in. Pages already render incrementally via the
         IntersectionObserver, so this only shows pre-onMount. -->
    {#if !loadError && pages.length === 0}
      <div class="skeleton-page" aria-hidden="true"></div>
      <div class="skeleton-page" aria-hidden="true"></div>
      <p class="loading-text" role="status" aria-live="polite">Loading book…</p>
    {/if}

    {#each pages as p (p.pageNum)}
      <div
        class="page"
        data-page-num={p.pageNum}
        style:width="{pageDisplayWidth}px"
        style:height="{pageDisplayHeight}px"
        bind:this={p.container}
      >
        <canvas bind:this={p.canvas} aria-label="Page {p.pageNum}"></canvas>

        <!-- Highlight layer: semi-transparent tints beneath the text layer so
             annotated text regions are discoverable without reading every marker.
             Sits below the text layer (z-index 1) so it doesn't block selection. -->
        <div class="highlight-layer" aria-hidden="true">
          {#each annotationsByPage.get(p.pageNum) || [] as a (a.id)}
            <div
              class="annotation-highlight"
              class:type-comment={a.type === "comment" || !a.type}
              class:type-question={a.type === "question"}
              class:type-puzzle={a.type === "puzzle"}
              class:type-ai={a.type === "ai_response"}
              class:is-hovered={hoveredAnnotationId === a.id}
              style:left="{a.rect.x * 100}%"
              style:top="{a.rect.y * 100}%"
              style:width="{a.rect.width * 100}%"
              style:height="{a.rect.height * 100}%"
            ></div>
          {/each}
          {#each searchHighlightsByPage.get(p.pageNum) || [] as h, i (i)}
            <div
              class="search-highlight"
              class:search-current={searchResults[searchResultIndex]?.page === p.pageNum}
              style:left="{h.x * 100}%"
              style:top="{h.y * 100}%"
              style:width="{h.width * 100}%"
              style:height="{h.height * 100}%"
            ></div>
          {/each}
          {#each localHighlights.filter((h) => h.page === p.pageNum) as h (h.id)}
            <div
              class="local-highlight"
              style:left="{h.rect.x * 100}%"
              style:top="{h.rect.y * 100}%"
              style:width="{h.rect.width * 100}%"
              style:height="{h.rect.height * 100}%"
            ></div>
          {/each}
        </div>

        <div class="textLayer" bind:this={p.textLayer}></div>
        <div class="annotation-overlay">
          {#each annotationsByPage.get(p.pageNum) || [] as a (a.id)}
            <button
              type="button"
              class="annotation-marker"
              class:is-active={a.id === active_annotation_id}
              class:is-pulse={a.id === pulseAnnotationId}
              class:is-dim={hoveredAnnotationId &&
                hoveredAnnotationId !== a.id}
              data-annotation-id={a.id}
              style:left="{(a.rect.x + a.rect.width) * 100}%"
              style:top="{a.rect.y * 100}%"
              aria-label="Annotation {a.number}, page {a.page}"
              onclick={(e) => onMarkerClick(e, a.id)}
              onmouseenter={() => dispatchMarkerHover(a.id)}
              onmouseleave={() => dispatchMarkerHover(null)}
              onfocus={() => dispatchMarkerHover(a.id)}
              onblur={() => dispatchMarkerHover(null)}
            >
              <span class="marker-num">{a.number}</span>
            </button>
          {/each}

          {#each milestonesByPage.get(p.pageNum) || [] as m (m.id)}
            {@const stampCount = (stampsByMilestone.get(m.id) || []).length}
            {@const stampedByMe =
              current_user_id != null &&
              (stampsByMilestone.get(m.id) || []).some(
                (s) => s.user_id === current_user_id,
              )}
            <button
              type="button"
              class="milestone-marker"
              class:is-stamped={stampedByMe}
              data-milestone-id={m.id}
              style:left="{(m.position?.x ?? 0) * 100}%"
              style:top="{(m.position?.y ?? 0) * 100}%"
              aria-label={`Milestone: ${m.label} · ${stampCount} of ${total_readers} readers`}
              title={m.label}
              onclick={(e) => onMilestoneMarkerClick(e, m.id)}
            >
              <span class="milestone-flag" aria-hidden="true"></span>
              <span class="milestone-label">{m.label}</span>
              {#if stampCount > 0}
                <span class="milestone-count num">{stampCount}</span>
              {/if}
            </button>
          {/each}
        </div>

        <!-- Page presence: faint ambient badge showing other readers on this page -->
        {#if pageReadersMap.has(p.pageNum)}
          {@const pr = pageReadersMap.get(p.pageNum)}
          <div class="page-presence" aria-label="{pr.count} {pr.count === 1 ? 'reader' : 'readers'} here">
            <span class="presence-dot" aria-hidden="true"></span>
            <span class="presence-label">{pr.count} {pr.count === 1 ? 'reader' : 'readers'} here</span>
          </div>
        {/if}
      </div>
    {/each}
  </div>

  <!-- Annotation density heatmap — moved inside reader-body so it's scoped
       to the scroll viewport rather than the full reader height. -->
  {#if annotations.length > 0 && pages.length > 0}
    <div class="density-heatmap" aria-hidden="true">
      {#each annotations as a (a.id)}
        <button
          class="density-tick"
          class:type-comment={a.type === "comment" || !a.type}
          class:type-question={a.type === "question"}
          class:type-puzzle={a.type === "puzzle"}
          class:type-ai={a.type === "ai_response"}
          style:top="{((a.page - 1) / Math.max(pages.length - 1, 1)) * 100}%"
          onclick={() => scrollToPage(a.page)}
          title="Annotation · page {a.page}"
          tabindex="-1"
        ></button>
      {/each}
      <div class="density-viewport" style:top="{heatmapViewportTop}%"></div>
    </div>
  {/if}

  <!-- First-use hint moved inside reader-body so its absolute positioning
       is scoped to the scroll area, not the full reader. -->
  {#if annotations.length === 0 && pages.length > 0 && !selectionMenu}
    <div class="first-use-hint" role="note" aria-label="Getting started hint">
      <span class="hint-icon" aria-hidden="true">↑</span>
      <p class="hint-text">Select any text to add your first annotation</p>
    </div>
  {/if}

  </div><!-- end .reader-body -->

  {#if milestonePopover && popoverContext}
    <div
      class="milestone-popover"
      style:left="{milestonePopover.x}px"
      style:top="{milestonePopover.y}px"
      role="dialog"
      aria-label={`Milestone: ${popoverContext.milestone.label}`}
    >
      <p class="popover-label">{popoverContext.milestone.label}</p>
      <p class="popover-meta">
        <span class="num">{popoverContext.stamps.length}</span>
        <span> / </span>
        <span class="num">{total_readers}</span>
        <span> readers</span>
      </p>

      {#if popoverContext.stamps.length > 0}
        <ul class="popover-avatars" aria-label="Readers who've stamped">
          {#each popoverContext.stamps as s (s.id)}
            <li
              class="popover-avatar"
              class:is-self={current_user_id != null &&
                s.user_id === current_user_id}
              title={s.email || "unknown"}
            >
              {emailInitials(s.email)}
            </li>
          {/each}
        </ul>
      {/if}

      {#if stampConfirmedMilestoneId === popoverContext.milestone.id}
        <!-- Brief impact confirmation before the popover closes -->
        <p class="popover-stamp-confirmed" aria-live="polite">Stamped.</p>
      {:else if popoverContext.stampedByMe}
        <p class="popover-stamped">Stamped by you</p>
      {:else}
        <button
          type="button"
          class="popover-stamp-btn"
          onmousedown={confirmStamp}
        >
          Stamp this milestone
        </button>
      {/if}
    </div>
  {/if}

  {#if selectionMenu}
    <div
      class="selection-menu"
      style:left="{selectionMenu.x}px"
      style:top="{selectionMenu.y}px"
      role="dialog"
      aria-label="Annotation actions"
    >
      <button
        class="selection-btn selection-btn-highlight"
        data-type="highlight"
        onmousedown={(e) => commitHighlight(e)}
      >
        <span>Highlight</span><kbd>H</kbd>
      </button>
      <button
        class="selection-btn"
        data-type="comment"
        onmousedown={(e) => commitSelection(e, "comment")}
      >
        <span>+ Add comment</span><kbd>C</kbd>
      </button>
      <button
        class="selection-btn"
        data-type="question"
        onmousedown={(e) => commitSelection(e, "question")}
      >
        <span>+ Ask question</span><kbd>Q</kbd>
      </button>
      <button
        class="selection-btn"
        data-type="puzzle"
        onmousedown={(e) => commitSelection(e, "puzzle")}
      >
        <span>+ Create puzzle</span><kbd>P</kbd>
      </button>
      <button
        class="selection-btn selection-btn-ai"
        data-type="ai"
        onmousedown={(e) => commitSelection(e, "ai")}
      >
        <span>+ Ask AI</span><kbd>A</kbd>
      </button>
      {#if is_admin}
        <button
          class="selection-btn selection-btn-divider"
          data-type="milestone"
          onmousedown={(e) => commitSelection(e, "milestone")}
        >
          <span>+ Place milestone</span><kbd>M</kbd>
        </button>
      {/if}
    </div>
  {/if}

  {#if showShortcuts}
    <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
    <div
      class="shortcuts-backdrop"
      onclick={(e) => { if (e.target === e.currentTarget) showShortcuts = false; }}
      role="dialog"
      aria-modal="true"
      aria-label="Keyboard shortcuts"
    >
      <div class="shortcuts-modal">
        <div class="shortcuts-header">
          <span class="shortcuts-title">Keyboard Shortcuts</span>
          <button
            class="shortcuts-close"
            onclick={() => (showShortcuts = false)}
            aria-label="Close shortcuts"
          >×</button>
        </div>

        <div class="shortcuts-groups">
          <section class="shortcuts-group">
            <h3 class="shortcuts-group-label">Navigation</h3>
            <ul class="shortcuts-list">
              <li><kbd>J</kbd><span class="shortcut-sep">/</span><kbd>↓</kbd><span class="shortcut-desc">Next page</span></li>
              <li><kbd>K</kbd><span class="shortcut-sep">/</span><kbd>↑</kbd><span class="shortcut-desc">Previous page</span></li>
              <li><kbd>[</kbd><span class="shortcut-desc">Previous annotation</span></li>
              <li><kbd>]</kbd><span class="shortcut-desc">Next annotation</span></li>
            </ul>
          </section>

          <section class="shortcuts-group">
            <h3 class="shortcuts-group-label">Zoom</h3>
            <ul class="shortcuts-list">
              <li><kbd>+</kbd><span class="shortcut-sep">/</span><kbd>=</kbd><span class="shortcut-desc">Zoom in</span></li>
              <li><kbd>−</kbd><span class="shortcut-desc">Zoom out</span></li>
              <li><kbd>0</kbd><span class="shortcut-desc">Reset to 100%</span></li>
              <li><kbd>⌘</kbd><span class="shortcut-sep">+</span><kbd>scroll</kbd><span class="shortcut-desc">Pinch zoom</span></li>
            </ul>
          </section>

          <section class="shortcuts-group">
            <h3 class="shortcuts-group-label">Search</h3>
            <ul class="shortcuts-list">
              <li><kbd>⌘F</kbd><span class="shortcut-desc">Open / close search</span></li>
              <li><kbd>Enter</kbd><span class="shortcut-desc">Next match</span></li>
              <li><kbd>⇧Enter</kbd><span class="shortcut-desc">Previous match</span></li>
              <li><kbd>Esc</kbd><span class="shortcut-desc">Close search</span></li>
            </ul>
          </section>

          <section class="shortcuts-group">
            <h3 class="shortcuts-group-label">Annotations</h3>
            <ul class="shortcuts-list">
              <li><kbd>H</kbd><span class="shortcut-desc">Highlight selection</span></li>
              <li><kbd>C</kbd><span class="shortcut-desc">Add comment (on selection)</span></li>
              <li><kbd>Q</kbd><span class="shortcut-desc">Ask question (on selection)</span></li>
              <li><kbd>P</kbd><span class="shortcut-desc">Create puzzle (on selection)</span></li>
              {#if is_admin}
                <li><kbd>M</kbd><span class="shortcut-desc">Place milestone (on selection)</span></li>
              {/if}
            </ul>
          </section>

          <section class="shortcuts-group">
            <h3 class="shortcuts-group-label">View</h3>
            <ul class="shortcuts-list">
              <li><span class="shortcut-btn">NRW / MED / WDE</span><span class="shortcut-desc">Cycle column width</span></li>
              <li><span class="shortcut-btn">DEF / SEPIA / NIGHT</span><span class="shortcut-desc">Cycle view mode</span></li>
              <li><span class="shortcut-btn">SNAP</span><span class="shortcut-desc">Toggle page snap</span></li>
              <li><span class="shortcut-btn">≡</span><span class="shortcut-desc">Toggle thumbnail strip</span></li>
              <li><kbd>?</kbd><span class="shortcut-desc">This cheatsheet</span></li>
              <li><kbd>Esc</kbd><span class="shortcut-desc">Close panels</span></li>
            </ul>
          </section>
        </div>
      </div>
    </div>
  {/if}
</div>

<style>
  .reader {
    display: flex;
    flex-direction: column;
    height: 100%;
    width: 100%;
    background: var(--color-paper);
    position: relative;
  }

  /* reader-body: flex row containing the optional thumb strip + scroll area.
     position: relative anchors the heatmap and first-use-hint overlays. */
  .reader-body {
    flex: 1;
    display: flex;
    overflow: hidden;
    position: relative;
  }

  /* ── Thumbnail strip ─────────────────────────────────────────────────────── */

  .thumb-panel {
    width: 100px;
    flex-shrink: 0;
    overflow-y: auto;
    overflow-x: hidden;
    background: var(--color-paper-2);
    border-right: 1px solid color-mix(in srgb, var(--color-ink-soft) 12%, transparent);
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    padding: 0.6rem 0.4rem;
    scrollbar-width: thin;
    scrollbar-color: var(--color-paper-2) transparent;
  }

  .thumb-item {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.2rem;
    border: 2px solid transparent;
    border-radius: 2px;
    padding: 0.15rem;
    cursor: pointer;
    background: transparent;
    transition: border-color 0.1s ease;
    width: 100%;
  }

  .thumb-item canvas {
    display: block;
    width: 80px;
    height: auto;
    background: white;
    box-shadow: 0 0 0 1px color-mix(in srgb, var(--color-ink-soft) 15%, transparent);
  }

  .thumb-item:hover {
    border-color: color-mix(in srgb, var(--color-terracotta) 35%, transparent);
  }

  .thumb-item.is-current {
    border-color: var(--color-terracotta);
  }

  .thumb-num {
    font-family: var(--font-mono);
    font-size: 0.55rem;
    color: var(--color-ink-soft);
    text-transform: uppercase;
    letter-spacing: 0.1em;
    font-variant-numeric: tabular-nums;
  }

  .thumb-item.is-current .thumb-num {
    color: var(--color-terracotta);
  }

  /* ── Chapter breadcrumb ──────────────────────────────────────────────────── */

  .chapter-crumb {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--color-ink-soft);
    text-transform: uppercase;
    letter-spacing: 0.1em;
    max-width: 18ch;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    opacity: 0.75;
  }

  .thumb-toggle {
    font-size: 0.9rem;
    padding: 0.1rem 0.4rem;
  }

  .indicator {
    position: sticky;
    top: 0;
    z-index: 5;
    padding: 0.5rem 1.5rem;
    font-family: var(--font-mono);
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.15em;
    color: var(--color-ink-soft);
    background: var(--color-paper);
    border-bottom: 1px solid var(--color-paper-2);
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .indicator .num {
    font-variant-numeric: tabular-nums;
  }

  .indicator .sep {
    opacity: 0.6;
  }

  .spacer {
    flex: 1;
  }

  .zoom-btn {
    border: none;
    background: transparent;
    color: var(--color-ink-soft);
    cursor: pointer;
    font-family: var(--font-mono);
    font-size: 0.95rem;
    line-height: 1;
    padding: 0.15rem 0.55rem;
    border-radius: 2px;
    transition:
      color 0.1s ease,
      background 0.1s ease;
  }

  .zoom-btn:hover:not(:disabled) {
    color: var(--color-terracotta);
    background: var(--color-paper-2);
  }

  .zoom-btn:disabled {
    opacity: 0.35;
    cursor: not-allowed;
  }

  .zoom-percent {
    min-width: 3rem;
    text-align: center;
    font-variant-numeric: tabular-nums;
  }

  .scroll {
    flex: 1;
    min-width: 0; /* prevent flex blowout when pages are wide */
    overflow-y: auto;
    overflow-x: auto;
    padding: 2rem 1rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1rem;
  }

  .page {
    background: white;
    box-shadow: 0 0 0 1px var(--color-paper-2);
    flex-shrink: 0;
    position: relative;
  }

  .page canvas {
    display: block;
    width: 100%;
    height: 100%;
  }

  /* Highlight layer: tinted rects behind the text layer marking annotated
     text regions. Sits at z-index 1 so the text layer (z-index 2) renders
     on top — selection stays fully functional. pointer-events: none on all
     children so the layer never captures clicks. */
  .highlight-layer {
    position: absolute;
    inset: 0;
    overflow: hidden;
    pointer-events: none;
    z-index: 1;
  }

  .annotation-highlight {
    position: absolute;
    pointer-events: none;
    border-bottom: 2px solid;
    /* Faint tint + underline — visible enough to find but not distracting */
    opacity: 0.55;
  }

  .annotation-highlight.type-comment {
    background: color-mix(in srgb, #f0c8a8 30%, transparent);
    border-bottom-color: #d4a87a;
  }

  .annotation-highlight.type-question {
    background: color-mix(in srgb, #c2dcc6 35%, transparent);
    border-bottom-color: #85b88e;
  }

  .annotation-highlight.type-puzzle {
    background: color-mix(in srgb, #d2c8e0 35%, transparent);
    border-bottom-color: #a094b8;
  }

  .annotation-highlight.type-ai {
    background: color-mix(in srgb, #ecdfa8 35%, transparent);
    border-bottom-color: #c9b86a;
  }

  .local-highlight {
    position: absolute;
    pointer-events: none;
    background: color-mix(in srgb, #f5e030 55%, transparent);
    border-radius: 1px;
  }

  /* Text layer: PDF.js positions transparent text spans over the canvas.
     Pattern adapted from pdfjs-dist/web/pdf_viewer.css. */
  .textLayer {
    position: absolute;
    inset: 0;
    overflow: hidden;
    line-height: 1;
    text-align: initial;
    forced-color-adjust: none;
    transform-origin: 0 0;
    z-index: 2;
  }

  .textLayer :global(span),
  .textLayer :global(br) {
    color: transparent;
    position: absolute;
    white-space: pre;
    cursor: text;
    transform-origin: 0% 0%;
  }

  .textLayer :global(::selection) {
    background: color-mix(in srgb, var(--color-terracotta) 30%, transparent);
  }

  /* Annotation markers overlay — sits above text layer (z-index 2) so markers
     are always clickable. Overlay itself is pointer-events: none; only the
     individual marker buttons re-enable pointer events. */
  .annotation-overlay {
    position: absolute;
    inset: 0;
    pointer-events: none;
    z-index: 3;
  }

  /* Annotation markers — small yellow badge with the footnote number
     centered inside, anchored at the end of the annotated rect on each
     page. The yellow ("butter") tint is one of the §5.1 highlight pastels
     so the marker reads as a paper-style sticky note rather than a UI
     control. Bumped from a quiet superscript to a more prominent badge
     so peer notes register at a glance during reading. */
  .annotation-marker {
    position: absolute;
    transform: translate(-2px, -50%);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 1.5rem;
    height: 1.5rem;
    font-family: var(--font-mono);
    color: var(--color-ink);
    font-size: 0.78rem;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    line-height: 1;
    pointer-events: auto;
    cursor: pointer;
    background: #f5d86e;
    border: 1px solid color-mix(in srgb, var(--color-terracotta) 25%, transparent);
    padding: 0;
    border-radius: 3px;
    transition:
      opacity 0.12s ease,
      background-color 0.12s ease,
      border-color 0.12s ease,
      transform 0.12s ease;
  }

  .annotation-marker:hover {
    background: #f1cd4a;
    border-color: color-mix(in srgb, var(--color-terracotta) 50%, transparent);
  }

  .annotation-marker:focus-visible {
    outline: 1px solid var(--color-terracotta);
    outline-offset: 2px;
  }

  .annotation-marker .marker-num {
    /* Force a normal flow inside the flex centre — without this an inline
       baseline can drift the digit a hair below the visual centre. */
    display: block;
    line-height: 1;
  }

  .annotation-marker.is-active {
    background: #f1cd4a;
    border-color: var(--color-terracotta);
  }

  .annotation-marker.is-dim {
    opacity: 0.25;
  }

  .annotation-marker.is-pulse {
    animation: marker-pulse 1.2s ease-out;
  }

  @keyframes marker-pulse {
    0% {
      box-shadow: 0 0 0 0 color-mix(in srgb, var(--color-terracotta) 55%, transparent);
      transform: translate(-2px, -50%) scale(1);
    }
    40% {
      transform: translate(-2px, -50%) scale(1.35);
    }
    100% {
      box-shadow: 0 0 0 14px color-mix(in srgb, var(--color-terracotta) 0%, transparent);
      transform: translate(-2px, -50%) scale(1);
    }
  }

  /* Milestone markers (Slice 12) — admin-placed checkpoints. Rendered as a
     small terracotta flag on a vertical stem with a mono-caps label flag.
     Visually distinct from annotation footnote markers so a reader can read
     the difference at a glance: annotations are quiet superscripts in the
     prose; milestones are flags planted alongside it.
     Clickable in Slice 13 — opens the stamp popover. */
  .milestone-marker {
    position: absolute;
    transform: translate(-50%, -100%);
    display: flex;
    align-items: flex-end;
    pointer-events: auto;
    z-index: 3;
    line-height: 1;
    background: transparent;
    border: none;
    padding: 0;
    cursor: pointer;
  }

  .milestone-marker:focus-visible {
    outline: 1px solid var(--color-terracotta);
    outline-offset: 2px;
    border-radius: 2px;
  }

  .milestone-marker.is-stamped .milestone-flag,
  .milestone-marker.is-stamped .milestone-flag::before {
    background: color-mix(in srgb, var(--color-terracotta) 70%, var(--color-ink));
  }

  .milestone-count {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 1.25rem;
    height: 1.25rem;
    margin-left: 0.3rem;
    padding: 0 0.3rem;
    margin-bottom: -0.2rem;
    border-radius: 999px;
    background: var(--color-terracotta);
    color: var(--color-paper);
    font-family: var(--font-mono);
    font-size: 0.6rem;
    font-variant-numeric: tabular-nums;
    line-height: 1;
  }

  .milestone-flag {
    display: inline-block;
    width: 2px;
    height: 22px;
    background: var(--color-terracotta);
    margin-right: -1px;
    flex-shrink: 0;
  }

  .milestone-flag::before {
    content: "";
    display: block;
    width: 10px;
    height: 8px;
    background: var(--color-terracotta);
    transform: translate(2px, 0);
    clip-path: polygon(0 0, 100% 50%, 0 100%);
  }

  .milestone-label {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    color: var(--color-terracotta);
    background: color-mix(in srgb, var(--color-paper) 92%, transparent);
    border: 1px solid color-mix(in srgb, var(--color-terracotta) 35%, transparent);
    padding: 0.15rem 0.4rem;
    margin-left: 0.4rem;
    margin-bottom: -0.15rem;
    border-radius: 2px;
    white-space: nowrap;
    max-width: 16rem;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* Milestone popover (Slice 13) — small dialog anchored to the marker the
     user clicked. Shows X/N readers, the avatar cluster of stampers, and
     either a stamp button or a "Stamped by you" indicator. */
  .milestone-popover {
    position: fixed;
    z-index: 50;
    background: var(--color-paper);
    border: 1px solid var(--color-paper-2);
    box-shadow: 0 2px 8px rgba(42, 37, 33, 0.08);
    padding: 0.75rem 0.85rem;
    border-radius: 2px;
    min-width: 14rem;
    max-width: 18rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .popover-label {
    font-family: var(--font-serif);
    color: var(--color-ink);
    font-size: 0.95rem;
    line-height: 1.25;
    margin: 0;
  }

  .popover-meta {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    text-transform: uppercase;
    letter-spacing: 0.15em;
    color: var(--color-ink-soft);
    margin: 0;
  }

  .popover-meta .num {
    font-variant-numeric: tabular-nums;
    color: var(--color-terracotta);
  }

  .popover-avatars {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-wrap: wrap;
    gap: 0.25rem;
  }

  .popover-avatar {
    width: 1.5rem;
    height: 1.5rem;
    border-radius: 999px;
    background: var(--color-paper-2);
    color: var(--color-ink-soft);
    font-family: var(--font-mono);
    font-size: 0.6rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .popover-avatar.is-self {
    background: var(--color-terracotta);
    color: var(--color-paper);
  }

  .popover-stamped {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    text-transform: uppercase;
    letter-spacing: 0.15em;
    color: var(--color-terracotta);
    border-top: 1px solid var(--color-paper-2);
    margin: 0;
    padding-top: 0.55rem;
  }

  /* Brief "Stamped." confirmation — shown for ~700ms before the popover
     closes. Larger text and a bounce-in animation for impact. */
  .popover-stamp-confirmed {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    text-transform: uppercase;
    letter-spacing: 0.18em;
    color: var(--color-terracotta);
    border-top: 1px solid var(--color-paper-2);
    margin: 0;
    padding-top: 0.55rem;
    animation: stamp-confirm 0.45s cubic-bezier(0.18, 0.89, 0.32, 1.28);
  }

  @keyframes stamp-confirm {
    0% { opacity: 0; transform: scale(0.85); }
    100% { opacity: 1; transform: scale(1); }
  }

  /* Stamp button — larger than a typical popover action to signal this is
     the primary affordance. Full-width so it's easy to hit. */
  .popover-stamp-btn {
    border: 1px solid var(--color-terracotta);
    background: var(--color-terracotta);
    color: var(--color-paper);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.15em;
    padding: 0.65rem 0.85rem;
    cursor: pointer;
    border-radius: 2px;
    width: 100%;
    text-align: center;
    transition:
      opacity 0.12s ease,
      transform 0.1s ease;
  }

  .popover-stamp-btn:hover {
    opacity: 0.88;
  }

  .popover-stamp-btn:active {
    transform: scale(0.97);
  }

  /* First-use hint — a quiet, animated nudge in the scroll area when the
     PDF has loaded but the user has no annotations yet. Fades in after a
     short delay and pulses gently to draw the eye. */
  .first-use-hint {
    position: absolute;
    bottom: 2rem;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: var(--color-paper);
    border: 1px solid var(--color-paper-2);
    padding: 0.55rem 1rem;
    border-radius: 999px;
    pointer-events: none;
    z-index: 10;
    animation:
      hint-fade-in 0.6s ease 1.2s both,
      hint-pulse 3s ease-in-out 1.8s infinite;
    white-space: nowrap;
  }

  .hint-icon {
    font-size: 0.85rem;
    color: var(--color-terracotta);
    animation: hint-bounce 1.8s ease-in-out 1.8s infinite;
    display: inline-block;
  }

  .hint-text {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    text-transform: uppercase;
    letter-spacing: 0.14em;
    color: var(--color-ink-soft);
    margin: 0;
  }

  @keyframes hint-fade-in {
    from { opacity: 0; transform: translateX(-50%) translateY(6px); }
    to { opacity: 1; transform: translateX(-50%) translateY(0); }
  }

  @keyframes hint-pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.6; }
  }

  @keyframes hint-bounce {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-3px); }
  }

  .selection-menu {
    position: fixed;
    z-index: 50;
    background: var(--color-paper);
    border: 1px solid var(--color-paper-2);
    box-shadow: 0 2px 8px rgba(42, 37, 33, 0.08);
    padding: 0.25rem;
    border-radius: 2px;
    display: flex;
    flex-direction: column;
    min-width: 12rem;
  }

  .selection-btn {
    border: none;
    background: transparent;
    color: var(--color-ink);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    padding: 0.4rem 0.75rem;
    cursor: pointer;
    border-radius: 2px;
    text-align: left;
  }

  .selection-btn:hover {
    color: var(--color-terracotta);
    background: var(--color-paper-2);
  }

  /* Highlight button — yellow tint on hover to preview the highlight colour. */
  .selection-btn-highlight:hover {
    color: var(--color-ink);
    background: color-mix(in srgb, #f5e030 35%, transparent);
  }

  /* Slice 11 — AI option sits between the annotation types and the admin
     milestone divider. Butter tint on hover so it reads as a distinct
     action from the human annotation types. */
  .selection-btn-ai:hover {
    color: var(--color-ink);
    background: oklch(from var(--color-butter, #f5e6a3) l c h / 0.35);
  }

  /* Slice 12 (revised, take 2) — admin-only milestone option lives in the
     same selection menu as comment/question/puzzle. The divider sets it
     apart visually from the annotation actions: same row family, distinct
     destination (margin-column label form). */
  .selection-btn-divider {
    border-top: 1px solid var(--color-paper-2);
    margin-top: 0.2rem;
    padding-top: 0.5rem;
  }

  .error {
    font-family: var(--font-serif);
    color: var(--color-terracotta);
    padding: 2rem;
  }

  /* Slice 16.5 — initial-load skeleton. The page rectangles use the same
     box-shadow outline real pages get, so the layout doesn't jump as the
     real pages take their place. The shimmer is intentionally slow and
     low-contrast to match the quiet aesthetic. */
  .skeleton-page {
    width: min(70ch, 90%);
    height: 80vh;
    background: linear-gradient(
      90deg,
      var(--color-paper) 0%,
      color-mix(in srgb, var(--color-paper-2) 60%, var(--color-paper)) 50%,
      var(--color-paper) 100%
    );
    background-size: 200% 100%;
    animation: skeleton-shimmer 2.4s ease-in-out infinite;
    box-shadow: 0 0 0 1px var(--color-paper-2);
    flex-shrink: 0;
  }

  .loading-text {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.15em;
    color: var(--color-ink-soft);
    padding: 1rem;
  }

  @keyframes skeleton-shimmer {
    0%,
    100% {
      background-position: 100% 0;
    }
    50% {
      background-position: 0 0;
    }
  }

  /* ── Reading quality: indicator action buttons ───────────────────────────── */

  .indicator-btn {
    border: none;
    background: transparent;
    color: var(--color-ink-soft);
    cursor: pointer;
    font-family: var(--font-mono);
    font-size: 0.6rem;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    line-height: 1;
    padding: 0.15rem 0.45rem;
    border-radius: 2px;
    transition:
      color 0.1s ease,
      background 0.1s ease;
  }

  .indicator-btn:hover,
  .indicator-btn.is-active {
    color: var(--color-terracotta);
    background: var(--color-paper-2);
  }

  /* ── Reading quality: column width ───────────────────────────────────────── */

  /* Narrow: center a constrained column, more margin on each side */
  .reader.width-narrow .scroll {
    align-items: center;
  }

  .reader.width-narrow .page {
    max-width: 580px;
  }

  /* Wide: let pages use all available horizontal space */
  .reader.width-wide .scroll {
    align-items: flex-start;
  }

  /* Medium (default): current behavior — no override needed */

  /* ── Reading quality: sepia mode ──────────────────────────────────────────── */

  .reader.mode-sepia canvas {
    filter: sepia(50%) brightness(0.97) contrast(0.96);
    transition: filter 0.3s ease;
  }

  /* ── Reading quality: night mode ─────────────────────────────────────────── */

  .reader.mode-night {
    background: #1c1814;
  }

  .reader.mode-night .indicator,
  .reader.mode-night .search-bar {
    background: #1c1814;
    border-color: #2d2824;
    color: #8c8075;
  }

  .reader.mode-night .indicator .num,
  .reader.mode-night .indicator .sep,
  .reader.mode-night .indicator .zoom-percent {
    color: #7a7068;
  }

  .reader.mode-night .scroll {
    background: #1c1814;
  }

  .reader.mode-night .page {
    box-shadow: 0 0 0 1px #2d2824;
  }

  /* Invert the PDF canvas; re-invert overlays so annotation colors stay true */
  .reader.mode-night canvas {
    filter: invert(0.9) hue-rotate(180deg) brightness(0.88);
    transition: filter 0.3s ease;
  }

  /* Re-invert highlight and annotation overlays so they keep their original
     hues — the page canvas is inverted under them, but we want the peach/
     mint/lavender tints to look like themselves, not their complements. */
  .reader.mode-night .highlight-layer {
    filter: invert(0.9) hue-rotate(180deg);
  }

  .reader.mode-night .annotation-overlay {
    filter: invert(0.9) hue-rotate(180deg);
  }

  /* ── Search toggle (indicator bar) ──────────────────────────────────────── */

  .search-toggle {
    border: none;
    background: transparent;
    color: var(--color-ink-soft);
    cursor: pointer;
    font-size: 1rem;
    line-height: 1;
    padding: 0.15rem 0.45rem;
    border-radius: 2px;
    transition:
      color 0.1s ease,
      background 0.1s ease;
    font-family: inherit;
  }

  .search-toggle:hover,
  .search-toggle.is-active {
    color: var(--color-terracotta);
    background: var(--color-paper-2);
  }

  /* ── Search bar (sticky row below indicator) ─────────────────────────────── */

  .search-bar {
    position: sticky;
    top: 0;
    z-index: 5;
    display: flex;
    align-items: center;
    gap: 0.25rem;
    padding: 0.4rem 1rem;
    background: var(--color-paper);
    border-bottom: 1px solid var(--color-paper-2);
    font-family: var(--font-mono);
    font-size: 0.7rem;
  }

  .search-icon {
    color: var(--color-ink-soft);
    font-size: 1rem;
    flex-shrink: 0;
  }

  .search-input {
    flex: 1;
    border: none;
    background: transparent;
    color: var(--color-ink);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    outline: none;
    padding: 0.15rem 0;
    min-width: 0;
  }

  .search-input::placeholder {
    color: color-mix(in srgb, var(--color-ink-soft) 50%, transparent);
  }

  .search-status {
    color: var(--color-ink-soft);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
    flex-shrink: 0;
    font-size: 0.65rem;
    text-transform: uppercase;
    letter-spacing: 0.1em;
  }

  .search-nav,
  .search-close {
    border: none;
    background: transparent;
    color: var(--color-ink-soft);
    cursor: pointer;
    font-family: var(--font-mono);
    font-size: 0.8rem;
    line-height: 1;
    padding: 0.2rem 0.4rem;
    border-radius: 2px;
    flex-shrink: 0;
    transition: color 0.1s ease, background 0.1s ease;
  }

  .search-nav:hover:not(:disabled),
  .search-close:hover {
    color: var(--color-terracotta);
    background: var(--color-paper-2);
  }

  .search-nav:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  /* ── Search highlights in the highlight layer ────────────────────────────── */

  .search-highlight {
    position: absolute;
    pointer-events: none;
    background: color-mix(in srgb, #f5c842 45%, transparent);
    border-bottom: 2px solid #d4a020;
    opacity: 0.7;
  }

  .search-highlight.search-current {
    background: color-mix(in srgb, #f5c842 70%, transparent);
    border-bottom-color: var(--color-terracotta);
    opacity: 1;
  }

  /* ── Annotation density heatmap ──────────────────────────────────────────── */

  .density-heatmap {
    position: absolute;
    right: 0;
    top: 0; /* .reader-body starts below the indicator, so no offset needed */
    bottom: 0;
    width: 7px;
    pointer-events: none;
    z-index: 4;
  }

  .density-tick {
    position: absolute;
    right: 1px;
    transform: translateY(-50%);
    width: 5px;
    height: 3px;
    border-radius: 1px;
    border: none;
    padding: 0;
    cursor: pointer;
    pointer-events: auto;
    opacity: 0.65;
    transition: opacity 0.1s ease, width 0.1s ease;
  }

  .density-tick:hover {
    opacity: 1;
    width: 7px;
  }

  .density-tick.type-comment { background: #d4a87a; }
  .density-tick.type-question { background: #85b88e; }
  .density-tick.type-puzzle { background: #a094b8; }
  .density-tick.type-ai { background: #c9b86a; }

  /* Viewport position indicator — a subtle bracket showing where the reader is */
  .density-viewport {
    position: absolute;
    right: 0;
    width: 2px;
    height: 12px;
    background: var(--color-terracotta);
    opacity: 0.5;
    border-radius: 1px;
    transform: translateY(-50%);
    pointer-events: none;
  }

  /* ── Reading timer ───────────────────────────────────────────────────────── */

  .reading-time {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: var(--color-ink-soft);
    opacity: 0.65;
    white-space: nowrap;
  }

  /* ── Annotation search mode tabs ─────────────────────────────────────────── */

  .search-mode-tabs {
    display: flex;
    gap: 0;
    border: 1px solid var(--color-paper-2);
    border-radius: 2px;
    overflow: hidden;
    flex-shrink: 0;
  }

  .search-mode-tab {
    border: none;
    background: transparent;
    color: var(--color-ink-soft);
    font-family: var(--font-mono);
    font-size: 0.6rem;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    padding: 0.2rem 0.5rem;
    cursor: pointer;
    transition: background 0.1s ease, color 0.1s ease;
  }

  .search-mode-tab.is-active {
    background: var(--color-terracotta);
    color: var(--color-paper);
  }

  .search-mode-tab:not(.is-active):hover {
    background: var(--color-paper-2);
    color: var(--color-terracotta);
  }

  /* ── Highlight echoes — pulse when a marker is hovered ───────────────────── */

  .annotation-highlight.is-hovered {
    animation: highlight-echo 0.7s ease-out;
  }

  @keyframes highlight-echo {
    0%   { opacity: 0.55; }
    25%  { opacity: 0.9; transform: scale(1.015); }
    100% { opacity: 0.55; transform: scale(1); }
  }

  /* ── Page presence badges ────────────────────────────────────────────────── */

  .page-presence {
    position: absolute;
    bottom: 0.6rem;
    right: 0.75rem;
    display: flex;
    align-items: center;
    gap: 0.3rem;
    pointer-events: none;
    z-index: 3;
    opacity: 0;
    animation: presence-fade-in 0.4s ease 0.3s both;
  }

  @keyframes presence-fade-in {
    from { opacity: 0; transform: translateY(4px); }
    to   { opacity: 1; transform: translateY(0); }
  }

  .presence-dot {
    width: 5px;
    height: 5px;
    border-radius: 50%;
    background: var(--color-terracotta);
    opacity: 0.6;
    animation: presence-pulse 2s ease-in-out infinite;
  }

  @keyframes presence-pulse {
    0%, 100% { opacity: 0.6; transform: scale(1); }
    50%       { opacity: 1;   transform: scale(1.2); }
  }

  .presence-label {
    font-family: var(--font-mono);
    font-size: 0.55rem;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    color: var(--color-terracotta);
    opacity: 0.75;
    white-space: nowrap;
  }

  /* ── Scroll-snap page transitions ───────────────────────────────────────── */

  .reader.snap-mode .scroll {
    scroll-snap-type: y mandatory;
  }

  .reader.snap-mode .page {
    scroll-snap-align: start;
  }

  /* ── Export link (indicator) ─────────────────────────────────────────────── */

  .export-link {
    text-decoration: none;
    font-size: 0.85rem;
    line-height: 1;
    display: inline-flex;
    align-items: center;
  }

  /* ── Keyboard shortcut cheatsheet modal ──────────────────────────────────── */

  .shortcuts-backdrop {
    position: fixed;
    inset: 0;
    z-index: 60;
    background: rgba(42, 37, 33, 0.35);
    display: flex;
    align-items: center;
    justify-content: center;
    animation: shortcuts-fade-in 0.15s ease;
  }

  @keyframes shortcuts-fade-in {
    from { opacity: 0; }
    to   { opacity: 1; }
  }

  .shortcuts-modal {
    background: var(--color-paper);
    border: 1px solid var(--color-paper-2);
    box-shadow: 0 4px 24px rgba(42, 37, 33, 0.12);
    border-radius: 3px;
    width: min(680px, 92vw);
    max-height: 80vh;
    overflow-y: auto;
    animation: shortcuts-slide-in 0.18s ease;
  }

  @keyframes shortcuts-slide-in {
    from { opacity: 0; transform: translateY(-6px); }
    to   { opacity: 1; transform: translateY(0); }
  }

  .shortcuts-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.85rem 1.2rem 0.7rem;
    border-bottom: 1px solid var(--color-paper-2);
  }

  .shortcuts-title {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.18em;
    color: var(--color-ink-soft);
  }

  .shortcuts-close {
    border: none;
    background: transparent;
    color: var(--color-ink-soft);
    font-family: var(--font-mono);
    font-size: 1rem;
    line-height: 1;
    padding: 0.2rem 0.4rem;
    border-radius: 2px;
    cursor: pointer;
    transition: color 0.1s ease, background 0.1s ease;
  }

  .shortcuts-close:hover {
    color: var(--color-terracotta);
    background: var(--color-paper-2);
  }

  .shortcuts-groups {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
    gap: 0;
    padding: 0.5rem 0;
  }

  .shortcuts-group {
    padding: 0.85rem 1.2rem;
    border-right: 1px solid var(--color-paper-2);
    border-bottom: 1px solid var(--color-paper-2);
  }

  .shortcuts-group:last-child {
    border-right: none;
  }

  .shortcuts-group-label {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    text-transform: uppercase;
    letter-spacing: 0.18em;
    color: var(--color-terracotta);
    margin: 0 0 0.7rem;
    font-weight: normal;
  }

  .shortcuts-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 0.45rem;
  }

  .shortcuts-list li {
    display: flex;
    align-items: center;
    gap: 0.3rem;
    flex-wrap: wrap;
  }

  .shortcuts-list kbd {
    font-family: var(--font-mono);
    font-size: 0.62rem;
    color: var(--color-ink);
    background: var(--color-paper-2);
    border: 1px solid color-mix(in srgb, var(--color-ink-soft) 25%, transparent);
    border-radius: 2px;
    padding: 0.1rem 0.35rem;
    line-height: 1.5;
    white-space: nowrap;
    flex-shrink: 0;
  }

  .shortcut-sep {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--color-ink-soft);
    opacity: 0.5;
  }

  .shortcut-desc {
    font-family: var(--font-mono);
    font-size: 0.62rem;
    color: var(--color-ink-soft);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    flex: 1;
    margin-left: 0.2rem;
  }

  /* For non-key labels like "NRW / MED / WDE" */
  .shortcut-btn {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--color-ink);
    background: var(--color-paper-2);
    border: 1px solid color-mix(in srgb, var(--color-ink-soft) 20%, transparent);
    border-radius: 2px;
    padding: 0.1rem 0.35rem;
    line-height: 1.5;
    white-space: nowrap;
    flex-shrink: 0;
  }

  /* ── Selection menu keyboard hints ──────────────────────────────────────── */

  .selection-btn {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 1rem;
  }

  .selection-btn kbd {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--color-ink-soft);
    background: var(--color-paper-2);
    border: 1px solid color-mix(in srgb, var(--color-ink-soft) 25%, transparent);
    border-radius: 2px;
    padding: 0.1rem 0.3rem;
    line-height: 1.4;
    flex-shrink: 0;
    opacity: 0.8;
  }

  .selection-btn:hover kbd {
    color: var(--color-terracotta);
    border-color: color-mix(in srgb, var(--color-terracotta) 35%, transparent);
  }
</style>
