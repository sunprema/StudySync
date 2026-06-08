<script>
  import { Handle, Position } from "@xyflow/svelte";
  import ReactionBar from "./ReactionBar.svelte";

  let { data, selected } = $props();

  let hovered = $state(false);

  const url = $derived(data?.content?.url || "");
  const title = $derived(data?.content?.title || url || "Web Link");
  const favicon = $derived(
    url ? `https://www.google.com/s2/favicons?domain=${new URL(url).hostname}&sz=32` : null
  );
  const hostname = $derived(url ? (() => { try { return new URL(url).hostname; } catch { return url; } })() : "");
</script>

<div
  class="link-node"
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

  <div class="link-inner">
    <div class="link-header">
      {#if favicon && url}
        <img src={favicon} alt="" class="favicon" />
      {:else}
        <span class="link-icon">🔗</span>
      {/if}
      <span class="hostname">{hostname}</span>
      {#if url}
        <a
          href={url}
          target="_blank"
          rel="noopener noreferrer"
          class="open-link"
          title="Open in new tab"
          onclick={(e) => e.stopPropagation()}
        >↗</a>
      {/if}
    </div>
    <p class="link-title">{title}</p>
  </div>

  <div class="node-badge-row">
    <span class="type-badge">Link</span>
  </div>
  <ReactionBar reactions={data?.reactions ?? []} onReact={data?.onReact} />
</div>

<style>
  .link-node {
    background: var(--color-paper, #f4efe3);
    border: 1.5px solid var(--color-ink-soft, #5c5750);
    border-radius: 4px;
    width: 220px;
    position: relative;
    cursor: default;
  }

  .link-node.selected {
    border-color: var(--color-terracotta, #b8512e);
    box-shadow: 0 0 0 2px var(--color-terracotta, #b8512e);
  }

  .link-node :global(.node-handle) {
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

  .link-node.show-handles :global(.node-handle) { opacity: 1; pointer-events: all; }
  .link-node :global(.node-handle:hover) {
    background: #ffd700 !important;
    border-color: #b8512e !important;
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

  .link-node.show-handles .delete-btn { opacity: 1; }

  .delete-btn:hover {
    background: var(--color-terracotta, #b8512e);
    border-color: var(--color-terracotta, #b8512e);
    color: #fff;
  }

  .link-inner {
    padding: 10px 12px 6px;
  }

  .link-header {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 6px;
  }

  .favicon {
    width: 16px;
    height: 16px;
    flex-shrink: 0;
  }

  .link-icon {
    font-size: 14px;
  }

  .hostname {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    color: var(--color-ink-soft, #5c5750);
    letter-spacing: 0.04em;
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .open-link {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    color: var(--color-terracotta, #b8512e);
    text-decoration: none;
    flex-shrink: 0;
  }

  .open-link:hover { text-decoration: underline; }

  .link-title {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    color: var(--color-ink, #2a2521);
    margin: 0;
    line-height: 1.4;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .node-badge-row {
    padding: 4px 8px;
    border-top: 1px solid var(--color-paper-2, #e8e0ce);
  }

  .type-badge {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--color-ink-soft, #5c5750);
    opacity: 0.6;
  }
</style>
