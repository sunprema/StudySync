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
  //   active_annotation_id : string  — id of the focused annotation; drives marker
  //                                     highlight and scroll-to-page on change
  //
  // Events to LiveView:
  //   text_selected      → { text, page, rect } when the user picks "Add Comment"
  //   annotation_clicked → { id } when the user clicks a marker in the prose
  let {
    file_url,
    total_pages = 0,
    annotations = [],
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
        for (const entry of entries) {
          const num = Number(entry.target.dataset.pageNum);
          if (entry.isIntersecting) {
            currentPage = num;
            if (!renderedPages.has(num)) {
              renderPage(num);
            }
          }
        }
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

  // Watch the document's selection so we can show the floating "Add Comment"
  // button whenever the user has a non-empty selection inside one of our pages.
  $effect(() => {
    if (!scrollEl) return;

    const handler = () => {
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

  function commitSelection(e) {
    // mousedown's preventDefault keeps focus on the page so the window
    // selection isn't cleared before our handler runs.
    e?.preventDefault?.();
    if (!selectionMenu) return;

    pushEvent("text_selected", {
      text: selectionMenu.text,
      page: selectionMenu.page,
      rect: selectionMenu.rect,
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

    {#each pages as p (p.pageNum)}
      <div
        class="page"
        data-page-num={p.pageNum}
        style:width="{pageDisplayWidth}px"
        style:height="{pageDisplayHeight}px"
        bind:this={p.container}
      >
        <canvas bind:this={p.canvas} aria-label="Page {p.pageNum}"></canvas>
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
              aria-label="Annotation {a.number}"
              onclick={(e) => onMarkerClick(e, a.id)}
            >
              <sup>{a.number}</sup>
            </button>
          {/each}
        </div>
      </div>
    {/each}
  </div>

  {#if selectionMenu}
    <div
      class="selection-menu"
      style:left="{selectionMenu.x}px"
      style:top="{selectionMenu.y}px"
      role="dialog"
      aria-label="Annotation actions"
    >
      <button class="selection-btn" onmousedown={commitSelection}>
        + Add comment
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

  .selection-menu {
    position: fixed;
    z-index: 50;
    background: var(--color-paper);
    border: 1px solid var(--color-paper-2);
    box-shadow: 0 2px 8px rgba(42, 37, 33, 0.08);
    padding: 0.25rem;
    border-radius: 2px;
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
</style>
