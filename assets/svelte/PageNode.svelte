<script>
  import { Handle, Position } from "@xyflow/svelte";
  import { getContext } from "svelte";
  import ReactionBar from "./ReactionBar.svelte";

  let { data, selected } = $props();

  const ctx = getContext("pdfDoc");

  let canvas = $state(null);
  let rendered = $state(false);
  let hovered = $state(false);

  const THUMB_WIDTH = 180;

  $effect(() => {
    const doc = ctx?.doc;
    if (doc && canvas && data?.page_number) {
      renderThumbnail(doc, data.page_number);
    }
  });

  async function renderThumbnail(doc, pageNum) {
    try {
      const page = await doc.getPage(pageNum);
      const viewport = page.getViewport({ scale: 1 });
      const scale = THUMB_WIDTH / viewport.width;
      const scaled = page.getViewport({ scale });
      canvas.width = scaled.width;
      canvas.height = scaled.height;
      await page.render({ canvasContext: canvas.getContext("2d"), viewport: scaled }).promise;
      rendered = true;
    } catch (_) {}
  }
</script>

<!-- role="presentation" — SvelteFlow's own wrapper div handles selection/focus -->
<div
  class="page-node"
  class:selected
  class:show-handles={hovered || selected}
  onmouseenter={() => (hovered = true)}
  onmouseleave={() => (hovered = false)}
  role="presentation"
>
  <Handle type="source" position={Position.Top}    id="t" class="node-handle" />
  <Handle type="source" position={Position.Right}  id="r" class="node-handle" />
  <Handle type="source" position={Position.Bottom} id="b" class="node-handle" />
  <Handle type="source" position={Position.Left}   id="l" class="node-handle" />

  <button
    class="delete-btn"
    title="Delete node"
    onclick={(e) => { e.stopPropagation(); data?.onDelete?.(); }}
  >✕</button>

  <div class="thumb-wrap">
    <canvas bind:this={canvas} class="thumb-canvas" class:visible={rendered}></canvas>
    {#if !rendered}
      <div class="thumb-placeholder">
        <span class="page-badge-lg">{data?.page_number ?? "?"}</span>
      </div>
    {/if}
    <button
      class="expand-btn"
      title="Open full page"
      onclick={() => data?.onExpand?.(data.page_number)}
    >
      ⤢
    </button>
  </div>

  <div class="node-footer">
    <span class="page-badge">P. {data?.page_number}</span>
    {#if data?.label}
      <span class="node-label">{data.label}</span>
    {/if}
  </div>
  <ReactionBar reactions={data?.reactions ?? []} onReact={data?.onReact} />
</div>

<style>
  .page-node {
    background: var(--color-paper-2, #e8e0ce);
    border: 1.5px solid var(--color-ink-soft, #5c5750);
    border-radius: 3px;
    width: 180px;
    cursor: default;
    position: relative;
  }

  .page-node.selected {
    border-color: var(--color-terracotta, #b8512e);
    box-shadow: 0 0 0 2px var(--color-terracotta, #b8512e);
  }

  /* Handles — square, large, yellow.
     pointer-events:none when hidden so they don't intercept node-selection clicks. */
  .page-node :global(.node-handle) {
    width: 16px !important;
    height: 16px !important;
    border-radius: 2px !important;
    background: #f5c518 !important;
    border: 2px solid #c49a00 !important;
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.12s;
    z-index: 10;
  }

  .page-node.show-handles :global(.node-handle) {
    opacity: 1;
    pointer-events: all;
  }

  .page-node :global(.node-handle:hover) {
    background: #ffd700 !important;
    border-color: #b8512e !important;
  }

  .thumb-wrap {
    position: relative;
    width: 180px;
    background: #fff;
    min-height: 100px;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    border-radius: 2px 2px 0 0;
  }

  .thumb-canvas {
    display: none;
    width: 100%;
    height: auto;
  }

  .thumb-canvas.visible {
    display: block;
  }

  .thumb-placeholder {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 180px;
    height: 120px;
    background: var(--color-paper-2, #e8e0ce);
  }

  .page-badge-lg {
    font-family: "JetBrains Mono", monospace;
    font-size: 28px;
    font-weight: 600;
    color: var(--color-ink-soft, #5c5750);
    opacity: 0.4;
  }

  .delete-btn {
    position: absolute;
    top: 3px;
    right: 3px;
    z-index: 20;
    width: 20px;
    height: 20px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--color-paper, #f4efe3);
    border: 1px solid var(--color-ink-soft, #5c5750);
    border-radius: 2px;
    font-size: 10px;
    color: var(--color-ink-soft, #5c5750);
    cursor: pointer;
    opacity: 0;
    transition: opacity 0.1s;
    padding: 0;
    line-height: 1;
  }

  .page-node.show-handles .delete-btn { opacity: 1; }

  .delete-btn:hover {
    background: var(--color-terracotta, #b8512e);
    border-color: var(--color-terracotta, #b8512e);
    color: #fff;
  }

  .expand-btn {
    position: absolute;
    top: 5px;
    right: 28px;
    background: var(--color-paper, #f4efe3);
    border: 1px solid var(--color-ink-soft, #5c5750);
    border-radius: 2px;
    font-size: 11px;
    line-height: 1;
    padding: 2px 4px;
    cursor: pointer;
    color: var(--color-ink-soft, #5c5750);
    opacity: 0;
    transition: opacity 0.1s;
  }

  .thumb-wrap:hover .expand-btn {
    opacity: 1;
  }

  .expand-btn:hover {
    color: var(--color-terracotta, #b8512e);
    border-color: var(--color-terracotta, #b8512e);
  }

  .node-footer {
    padding: 5px 8px;
    display: flex;
    align-items: baseline;
    gap: 6px;
    border-top: 1px solid var(--color-paper-2, #e8e0ce);
  }

  .page-badge {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--color-terracotta, #b8512e);
    white-space: nowrap;
  }

  .node-label {
    font-family: "JetBrains Mono", monospace;
    font-size: 10px;
    color: var(--color-ink, #2a2521);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 120px;
  }
</style>
