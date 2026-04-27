<script>
  import { onMount, onDestroy } from "svelte";
  import * as pdfjsLib from "pdfjs-dist";
  import workerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";

  // Wire the worker once at module init.
  pdfjsLib.GlobalWorkerOptions.workerSrc = workerUrl;

  // ---- Contract (CLAUDE.md §4.3) ----
  // Props from LiveView:
  //   file_url     : string   — URL to the PDF (auth-gated controller)
  //   total_pages  : number   — page count from the persisted resource
  // Slice 3 holds the page indicator inside this component; cross-boundary
  // events for selection/active annotation arrive in later slices.
  let { file_url, total_pages = 0 } = $props();

  let scrollEl = $state(null);
  let pages = $state([]); // array of { pageNum, container, canvas, rendered }
  let currentPage = $state(1);
  let loadError = $state(null);
  let pdfDoc = null;
  let observer = null;
  // Page numbers that have started/finished rendering. Kept off $state to avoid
  // pointless re-renders; the canvas itself displays the change.
  const renderedPages = new Set();
  const SCALE = 1.5;

  onMount(async () => {
    if (!file_url) return;

    try {
      const loadingTask = pdfjsLib.getDocument({ url: file_url });
      pdfDoc = await loadingTask.promise;

      const count = pdfDoc.numPages;
      // Build placeholder rows up-front; canvases size themselves once each
      // page is rendered. This keeps the scroll height correct from the start.
      pages = Array.from({ length: count }, (_, i) => ({
        pageNum: i + 1,
        container: null,
        canvas: null,
      }));
    } catch (e) {
      console.error("PdfCanvasRenderer: failed to load PDF", e);
      loadError = e?.message || "Failed to load PDF";
    }
  });

  onDestroy(() => {
    if (observer) observer.disconnect();
    if (pdfDoc) pdfDoc.destroy?.();
  });

  // Once the placeholders are in the DOM, attach an IntersectionObserver.
  // Pages near the viewport render; far pages stay as cheap placeholders.
  // CLAUDE.md §6: page virtualization, render only pages near the viewport.
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

  async function renderPage(num) {
    if (renderedPages.has(num)) return;
    renderedPages.add(num);

    const slot = pages[num - 1];
    if (!slot || !slot.canvas) {
      // Canvas not in the DOM yet; let the next observer pulse retry.
      renderedPages.delete(num);
      return;
    }

    try {
      const page = await pdfDoc.getPage(num);
      const viewport = page.getViewport({ scale: SCALE });
      const canvas = slot.canvas;
      const ctx = canvas.getContext("2d");
      canvas.width = viewport.width;
      canvas.height = viewport.height;
      canvas.style.width = `${viewport.width / window.devicePixelRatio}px`;
      canvas.style.height = `${viewport.height / window.devicePixelRatio}px`;
      await page.render({ canvasContext: ctx, viewport }).promise;
    } catch (e) {
      console.error(`PdfCanvasRenderer: render failed on page ${num}`, e);
      renderedPages.delete(num);
    }
  }
</script>

<div class="reader" data-testid="pdf-canvas-root">
  <header class="indicator">
    <span class="num">{currentPage}</span>
    <span class="sep">/</span>
    <span class="num">{pages.length || total_pages}</span>
  </header>

  <div class="scroll" bind:this={scrollEl}>
    {#if loadError}
      <p class="error">Couldn't load this PDF: {loadError}</p>
    {/if}

    {#each pages as p (p.pageNum)}
      <div
        class="page"
        data-page-num={p.pageNum}
        bind:this={p.container}
      >
        <canvas bind:this={p.canvas} aria-label={`Page ${p.pageNum}`}></canvas>
      </div>
    {/each}
  </div>
</div>

<style>
  .reader {
    display: flex;
    flex-direction: column;
    height: 100%;
    width: 100%;
    background: var(--color-paper);
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

  .scroll {
    flex: 1;
    overflow-y: auto;
    padding: 2rem 1rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1rem;
  }

  .page {
    background: white;
    box-shadow: 0 0 0 1px var(--color-paper-2);
    /* Reserve a sensible aspect ratio so the scroll height is correct before
       the page is rendered (a typical letter page is ~1:1.29). */
    aspect-ratio: 8.5 / 11;
    width: min(900px, 95%);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .page canvas {
    max-width: 100%;
    height: auto;
    display: block;
  }

  .error {
    font-family: var(--font-serif);
    color: var(--color-terracotta);
    padding: 2rem;
  }
</style>
