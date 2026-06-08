<script>
  import { Handle, Position } from "@xyflow/svelte";

  let { data, selected } = $props();

  let hovered = $state(false);

  const text = $derived(data?.content?.text || "");
  const pageNum = $derived(data?.content?.page_number);
  const annotationType = $derived(data?.content?.type || "comment");

  const typeColor = $derived({
    comment: "var(--color-terracotta, #b8512e)",
    question: "#5b7fa6",
    puzzle: "#7a5ea6",
    ai_response: "#4a9a7a",
  }[annotationType] || "var(--color-terracotta, #b8512e)");
</script>

<div
  class="quote-node"
  class:selected
  class:show-handles={hovered || selected}
  onmouseenter={() => (hovered = true)}
  onmouseleave={() => (hovered = false)}
  role="presentation"
  style="--type-color: {typeColor}"
>
  <Handle type="source" position={Position.Top}    id="t" class="node-handle" />
  <Handle type="source" position={Position.Right}  id="r" class="node-handle" />
  <Handle type="source" position={Position.Bottom} id="b" class="node-handle" />
  <Handle type="source" position={Position.Left}   id="l" class="node-handle" />

  <div class="quote-mark">"</div>

  <div class="quote-body">
    <p class="quote-text">{text || "No text captured"}</p>
  </div>

  <div class="quote-footer">
    <span class="type-badge" style="color: {typeColor}">{annotationType}</span>
    {#if pageNum}
      <span class="page-ref">p. {pageNum}</span>
    {/if}
  </div>
</div>

<style>
  .quote-node {
    background: var(--color-paper, #f4efe3);
    border: 1.5px solid var(--color-paper-2, #e8e0ce);
    border-left: 3px solid var(--type-color);
    border-radius: 3px;
    width: 220px;
    position: relative;
    cursor: default;
  }

  .quote-node.selected {
    border-color: var(--type-color);
    box-shadow: 0 0 0 2px color-mix(in srgb, var(--type-color) 30%, transparent);
  }

  .quote-node :global(.node-handle) {
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

  .quote-node.show-handles :global(.node-handle) { opacity: 1; pointer-events: all; }
  .quote-node :global(.node-handle:hover) {
    background: #ffd700 !important;
    border-color: #b8512e !important;
  }

  .quote-mark {
    font-family: "Instrument Serif", serif;
    font-size: 40px;
    line-height: 1;
    color: var(--type-color);
    opacity: 0.25;
    padding: 4px 10px 0;
    height: 28px;
    overflow: hidden;
  }

  .quote-body {
    padding: 0 12px 8px;
  }

  .quote-text {
    font-family: "Instrument Serif", serif;
    font-size: 12px;
    line-height: 1.55;
    color: var(--color-ink, #2a2521);
    font-style: italic;
    margin: 0;
    display: -webkit-box;
    -webkit-line-clamp: 5;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .quote-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 4px 10px;
    border-top: 1px solid var(--color-paper-2, #e8e0ce);
  }

  .type-badge {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
  }

  .page-ref {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    color: var(--color-ink-soft, #5c5750);
    opacity: 0.6;
  }
</style>
