<script>
  import { onMount, onDestroy } from "svelte";
  import * as pdfjsLib from "pdfjs-dist";
  import workerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";
  import { useLiveSvelte } from "live_svelte";

  pdfjsLib.GlobalWorkerOptions.workerSrc = workerUrl;

  // ---- Contract (CLAUDE.md §4.3) ----
  // Props from LiveView:
  //   file_url             : string  — auth-gated URL the canvas fetches the PDF from
  //   total_pages          : number  — page count from the persisted resource
  //   annotations          : array   — [{ id, number, page, rect: { x, y, width, height } }]
  //                                     rect coordinates are 0..1 normalized to the page
  //   milestone_markers    : array   — [{ id, page, position: { x, y }, label }]
  //                                     position is 0..1 normalized to the page
  //   milestone_mode       : bool    — when true, clicking a page emits
  //                                    `milestone_placed` instead of selecting text
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
  //                        "question" | "puzzle".
  //   annotation_clicked → { id } when the user clicks a marker in the prose
  //   milestone_placed   → { page, position: { x, y } } when an admin in
  //                        milestone_mode clicks a page to drop a checkpoint.
  //   apply_stamp        → { milestone_id } when the user confirms a stamp from
  //                        the milestone popover.
  //   pages_visible      → { first, last } emitted (debounced) whenever the set
  //                        of pages intersecting the viewport changes. The LV
  //                        uses `first` as the focal page so the margin column
  //                        can highlight cards on that page via background
  //                        color. (added Slice 15; revised Slice 15a)
  let {
    file_url,
    total_pages = 0,
    annotations = [],
    milestone_markers = [],
    milestone_mode = false,
    rubber_stamps = [],
    current_user_id = null,
    total_readers = 0,
    active_annotation_id = null,
  } = $props();

  const { pushEvent } = useLiveSvelte();

  let scrollEl = $state(null);
  let pages = $state([]);
  let currentPage = $state(1);
  let loadError = $state(null);
  // User-facing zoom percentage. 100 = comfortable reading default.
  let zoomPct = $state(100);
  let firstPageSize = $state(null);
  // Floating selection menu — { x, y, text, page, rect } or null.
  let selectionMenu = $state(null);
  // Milestone popover — { x, y, milestone_id } or null. Anchored next to the
  // marker the user clicked; shows X/N readers + avatar cluster + stamp button.
  let milestonePopover = $state(null);
  // Hover-linking state — set by document-level "studysync:annotation-hover"
  // events dispatched from the margin column. Pure client-side; no LV roundtrip.
  let hoveredAnnotationId = $state(null);
  // Marker that should briefly pulse — cleared after the animation completes.
  let pulseAnnotationId = $state(null);

  let pdfDoc = null;
  let observer = null;
  let pulseTimer = null;
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
      }));
    } catch (e) {
      console.error("PdfCanvasRenderer: failed to load PDF", e);
      loadError = e?.message || "Failed to load PDF";
    }
  });

  onDestroy(() => {
    if (observer) observer.disconnect();
    if (pdfDoc) pdfDoc.destroy?.();
    if (pulseTimer) clearTimeout(pulseTimer);
    if (visiblePagesDebounce) clearTimeout(visiblePagesDebounce);
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

      if (e.key === "Escape") {
        let consumed = false;
        if (milestonePopover) {
          closeMilestonePopover();
          consumed = true;
        }
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

      if (e.key === "j" || e.key === "ArrowDown") {
        e.preventDefault();
        scrollByPage(1);
      } else if (e.key === "k" || e.key === "ArrowUp") {
        e.preventDefault();
        scrollByPage(-1);
      } else if (e.key === "n" || e.key === "N") {
        if (selectionMenu) {
          e.preventDefault();
          commitSelection(e, "comment");
        }
      }
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

  // Watch the document's selection so we can show the floating "Add Comment"
  // button whenever the user has a non-empty selection inside one of our pages.
  $effect(() => {
    if (!scrollEl) return;

    const handler = () => {
      // While in milestone-placement mode, the page is "click to drop"
      // rather than "select to annotate" — keep the floating menu hidden.
      if (milestone_mode) {
        selectionMenu = null;
        return;
      }

      const sel = window.getSelection();
      if (!sel || sel.rangeCount === 0) {
        selectionMenu = null;
        return;
      }

      const text = sel.toString();
      if (text.trim() === "") {
        selectionMenu = null;
        return;
      }

      const range = sel.getRangeAt(0);
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
    };

    document.addEventListener("selectionchange", handler);
    return () => document.removeEventListener("selectionchange", handler);
  });

  // Slice 15.1/15.2 — push the current visible-page range to LV.
  // Debounced (120ms) so a fast scroll doesn't fire on every IO callback;
  // and de-duped so we don't ship the same range twice in a row.
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
      if (
        lastReportedRange &&
        lastReportedRange.first === first &&
        lastReportedRange.last === last
      ) {
        return;
      }
      lastReportedRange = { first, last };
      pushEvent("pages_visible", { first, last });
    }, 120);
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

  // Admin-only milestone placement (Slice 12). When `milestone_mode` is true
  // a transparent <button> overlays each page; clicking it normalises the
  // click point against the page rect (the button's parent) and ships
  // `{ page, position }` to LiveView for the label form. The overlay also
  // prevents text selection while placing so the floating "Add comment" menu
  // never competes with placement clicks.
  function onPageClick(e, pageNum) {
    if (!milestone_mode) return;

    const pageEl = e.currentTarget.closest("[data-page-num]");
    if (!pageEl) return;
    const rect = pageEl.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) return;

    e.preventDefault();
    e.stopPropagation();

    pushEvent("milestone_placed", {
      page: pageNum,
      position: {
        x: (e.clientX - rect.left) / rect.width,
        y: (e.clientY - rect.top) / rect.height,
      },
    });
  }

  // Click a milestone marker → open the popover anchored to the marker.
  // Coordinates are viewport-fixed so the popover stays put while the user
  // skims the popover content; closing on outside click resets state.
  function onMilestoneMarkerClick(e, milestone_id) {
    e.preventDefault();
    e.stopPropagation();
    if (milestone_mode) return;

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
    pushEvent("apply_stamp", { milestone_id: popoverContext.milestone.id });
    milestonePopover = null;
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
</script>

<div class="reader" data-testid="pdf-canvas-root">
  <header class="indicator">
    <span class="num">{currentPage}</span>
    <span class="sep">/</span>
    <span class="num">{pages.length || total_pages}</span>

    <span class="spacer"></span>

    <button
      class="zoom-btn"
      onclick={zoomOut}
      aria-label="Zoom out"
      disabled={zoomPct <= ZOOM_MIN}
    >
      −
    </button>
    <span class="zoom-percent num">{zoomPct}%</span>
    <button
      class="zoom-btn"
      onclick={zoomIn}
      aria-label="Zoom in"
      disabled={zoomPct >= ZOOM_MAX}
    >
      +
    </button>
  </header>

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
        class:is-placing={milestone_mode}
        data-page-num={p.pageNum}
        style:width="{pageDisplayWidth}px"
        style:height="{pageDisplayHeight}px"
        bind:this={p.container}
      >
        <canvas bind:this={p.canvas} aria-label="Page {p.pageNum}"></canvas>
        <div class="textLayer" bind:this={p.textLayer}></div>
        {#if milestone_mode}
          <button
            type="button"
            class="milestone-placer"
            aria-label="Place a milestone on page {p.pageNum}"
            onclick={(e) => onPageClick(e, p.pageNum)}
          ></button>
        {/if}
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
              <sup>{a.number}</sup>
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
      </div>
    {/each}
  </div>

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

      {#if popoverContext.stampedByMe}
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
        class="selection-btn"
        data-type="comment"
        onmousedown={(e) => commitSelection(e, "comment")}
      >
        + Add comment
      </button>
      <button
        class="selection-btn"
        data-type="question"
        onmousedown={(e) => commitSelection(e, "question")}
      >
        + Ask question
      </button>
      <button
        class="selection-btn"
        data-type="puzzle"
        onmousedown={(e) => commitSelection(e, "puzzle")}
      >
        + Create puzzle
      </button>
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

  .page.is-placing {
    cursor: crosshair;
  }

  .page.is-placing :global(.textLayer) {
    pointer-events: none;
    user-select: none;
  }

  /* Transparent overlay button — only present while in milestone-placement
     mode. Sits above the text layer / annotation overlay so its click wins,
     but the canvas paints through. Inheriting the page's crosshair cursor
     keeps the affordance consistent. */
  .milestone-placer {
    position: absolute;
    inset: 0;
    z-index: 4;
    background: transparent;
    border: none;
    padding: 0;
    margin: 0;
    cursor: crosshair;
  }

  .milestone-placer:focus-visible {
    outline: 2px solid var(--color-terracotta);
    outline-offset: -2px;
  }

  .page canvas {
    display: block;
    width: 100%;
    height: 100%;
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
    z-index: 1;
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

  /* Annotation markers — terracotta superscript, anchored at the end of the
     selection's rect on each page. Clickable via Slice 5 bi-directional sync. */
  .annotation-overlay {
    position: absolute;
    inset: 0;
    /* Overlay itself is transparent to pointer events so the underlying text
       layer keeps receiving selection drags; only the markers re-enable
       pointer-events for click. */
    pointer-events: none;
    z-index: 2;
  }

  .annotation-marker {
    position: absolute;
    transform: translate(-2px, -50%);
    font-family: var(--font-mono);
    color: var(--color-terracotta);
    font-size: 0.65rem;
    font-variant-numeric: tabular-nums;
    line-height: 1;
    pointer-events: auto;
    cursor: pointer;
    background: transparent;
    border: none;
    padding: 0.1rem 0.25rem;
    border-radius: 2px;
    transition:
      opacity 0.12s ease,
      background-color 0.12s ease,
      transform 0.12s ease;
  }

  .annotation-marker:hover {
    background: color-mix(in srgb, var(--color-terracotta) 14%, transparent);
  }

  .annotation-marker:focus-visible {
    outline: 1px solid var(--color-terracotta);
    outline-offset: 1px;
  }

  .annotation-marker sup {
    font-size: inherit;
  }

  .annotation-marker.is-active {
    background: color-mix(in srgb, var(--color-terracotta) 18%, transparent);
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

  .popover-stamp-btn {
    border: 1px solid var(--color-terracotta);
    background: var(--color-terracotta);
    color: var(--color-paper);
    font-family: var(--font-mono);
    font-size: 0.65rem;
    text-transform: uppercase;
    letter-spacing: 0.15em;
    padding: 0.5rem 0.75rem;
    cursor: pointer;
    border-radius: 2px;
    transition: opacity 0.12s ease;
  }

  .popover-stamp-btn:hover {
    opacity: 0.9;
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
</style>
