<script>
  import { Handle, Position } from "@xyflow/svelte";

  let { data, selected } = $props();

  let hovered = $state(false);
  let showPlayer = $state(false);

  function videoId(url) {
    if (!url) return null;
    const m = url.match(/(?:v=|youtu\.be\/|embed\/)([A-Za-z0-9_-]{11})/);
    return m ? m[1] : null;
  }

  const vid = $derived(videoId(data?.content?.url));
  const thumb = $derived(vid ? `https://img.youtube.com/vi/${vid}/hqdefault.jpg` : null);
  const title = $derived(data?.content?.title || data?.label || "YouTube");
</script>

<div
  class="yt-node"
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

  <div class="thumb-area">
    {#if thumb}
      <img src={thumb} alt={title} class="thumb-img" />
    {:else}
      <div class="thumb-empty">
        <span class="yt-icon">▶</span>
        <span class="yt-placeholder">Paste a YouTube URL</span>
      </div>
    {/if}
    {#if vid}
      <button class="play-btn" onclick={() => (showPlayer = true)} title="Play video">▶</button>
    {/if}
  </div>

  <div class="node-footer">
    <span class="yt-badge">YouTube</span>
    <span class="node-title">{title}</span>
  </div>
</div>

{#if showPlayer && vid}
  <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
  <div
    class="player-backdrop"
    onclick={(e) => { if (e.target === e.currentTarget) showPlayer = false; }}
    onkeydown={(e) => e.key === "Escape" && (showPlayer = false)}
    role="dialog"
    aria-modal="true"
    aria-label="YouTube player"
    tabindex="-1"
  >
    <div class="player-box">
      <div class="player-header">
        <span class="player-title">{title}</span>
        <button class="player-close" onclick={() => (showPlayer = false)}>✕</button>
      </div>
      <iframe
        src="https://www.youtube.com/embed/{vid}?autoplay=1"
        title={title}
        frameborder="0"
        allow="autoplay; encrypted-media; picture-in-picture"
        allowfullscreen
        class="player-iframe"
      ></iframe>
    </div>
  </div>
{/if}

<style>
  .yt-node {
    background: #1a1a1a;
    border: 1.5px solid #333;
    border-radius: 4px;
    width: 200px;
    position: relative;
    cursor: default;
  }

  .yt-node.selected {
    border-color: #ff0000;
    box-shadow: 0 0 0 2px #ff000044;
  }

  .yt-node :global(.node-handle) {
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

  .yt-node.show-handles :global(.node-handle) {
    opacity: 1;
    pointer-events: all;
  }

  .yt-node :global(.node-handle:hover) {
    background: #ffd700 !important;
    border-color: #b8512e !important;
  }

  .thumb-area {
    position: relative;
    width: 200px;
    height: 113px; /* 16:9 */
    overflow: hidden;
    background: #111;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 3px 3px 0 0;
  }

  .thumb-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .thumb-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
  }

  .yt-icon {
    font-size: 24px;
    color: #ff0000;
  }

  .yt-placeholder {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    color: #666;
    text-align: center;
  }

  .play-btn {
    position: absolute;
    inset: 0;
    background: rgba(0,0,0,0.45);
    border: none;
    color: #fff;
    font-size: 28px;
    cursor: pointer;
    opacity: 0;
    transition: opacity 0.15s;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .thumb-area:hover .play-btn {
    opacity: 1;
  }

  .node-footer {
    padding: 5px 8px;
    display: flex;
    align-items: baseline;
    gap: 6px;
    border-top: 1px solid #333;
  }

  .yt-badge {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: #ff0000;
    white-space: nowrap;
    flex-shrink: 0;
  }

  .node-title {
    font-family: "JetBrains Mono", monospace;
    font-size: 10px;
    color: #ccc;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* Player modal */
  .player-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.75);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 2000;
  }

  .player-box {
    background: #111;
    border-radius: 4px;
    overflow: hidden;
    width: min(800px, 90vw);
  }

  .player-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8px 12px;
    background: #1a1a1a;
  }

  .player-title {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    color: #aaa;
    letter-spacing: 0.04em;
  }

  .player-close {
    background: none;
    border: none;
    color: #888;
    font-size: 14px;
    cursor: pointer;
    padding: 2px 6px;
  }

  .player-close:hover { color: #fff; }

  .player-iframe {
    display: block;
    width: 100%;
    aspect-ratio: 16 / 9;
  }
</style>
