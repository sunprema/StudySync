<script>
  // NodeSidebar — draggable node-type palette for the concept map board.
  // Each card sets dataTransfer so ConceptMapBoard can create the right node on drop.

  let { annotations = [] } = $props();

  const nodeTypes = [
    {
      type: "page",
      icon: "📄",
      label: "Page",
      description: "A page from the book",
      color: "var(--color-terracotta, #b8512e)",
    },
    {
      type: "youtube",
      icon: "▶",
      label: "YouTube",
      description: "Embed a video",
      color: "#ff0000",
    },
    {
      type: "text",
      icon: "✏",
      label: "Concept",
      description: "A note or argument",
      color: "var(--color-ink-soft, #5c5750)",
    },
    {
      type: "quote",
      icon: '"',
      label: "Quote",
      description: "A passage from your annotations",
      color: "#5b7fa6",
    },
    {
      type: "link",
      icon: "↗",
      label: "Link",
      description: "A web reference",
      color: "var(--color-ink-soft, #5c5750)",
    },
  ];

  // Quote picker state — shown when user drops a quote node
  let showQuotePicker = $state(false);
  let pendingQuotePos = $state(null);

  // Exposed so ConceptMapBoard can trigger quote picker after a drop
  export function openQuotePicker(pos) {
    pendingQuotePos = pos;
    showQuotePicker = true;
  }

  import { createEventDispatcher } from "svelte";
  const dispatch = createEventDispatcher();

  function dragStart(e, type) {
    e.dataTransfer.effectAllowed = "copy";
    e.dataTransfer.setData("application/board-node-type", type);
  }

  function selectQuote(annotation) {
    if (!pendingQuotePos) return;
    dispatch("quotePicked", {
      pos: pendingQuotePos,
      annotation,
    });
    showQuotePicker = false;
    pendingQuotePos = null;
  }
</script>

<aside class="sidebar">
  <p class="sidebar-label">Nodes</p>

  {#each nodeTypes as nt}
    <!-- svelte-ignore a11y_no_noninteractive_element_to_interactive_role -->
    <div
      class="node-card"
      draggable="true"
      ondragstart={(e) => dragStart(e, nt.type)}
      role="button"
      tabindex="0"
      onkeydown={(e) => e.key === "Enter" && dispatch("addNode", { type: nt.type })}
      title={nt.description}
    >
      <span class="node-icon" style="color: {nt.color}">{nt.icon}</span>
      <span class="node-label">{nt.label}</span>
    </div>
  {/each}
</aside>

<!-- Quote picker modal -->
{#if showQuotePicker}
  <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
  <div
    class="picker-backdrop"
    onclick={(e) => { if (e.target === e.currentTarget) { showQuotePicker = false; pendingQuotePos = null; } }}
    onkeydown={(e) => e.key === "Escape" && (showQuotePicker = false)}
    role="dialog"
    aria-modal="true"
    aria-label="Pick a quote from annotations"
    tabindex="-1"
  >
    <div class="picker-box">
      <div class="picker-header">
        <span class="picker-title">Pick an annotation</span>
        <button class="picker-close" onclick={() => (showQuotePicker = false)}>✕</button>
      </div>
      <div class="picker-list">
        {#if annotations.length === 0}
          <p class="picker-empty">No annotations yet. Add some in the reader first.</p>
        {:else}
          {#each annotations as a}
            <button class="picker-item" onclick={() => selectQuote(a)}>
              <span class="picker-page">p. {a.page_number}</span>
              <span class="picker-type {a.type}">{a.type}</span>
              <span class="picker-text">{a.text || "(no text)"}</span>
            </button>
          {/each}
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .sidebar {
    width: 72px;
    flex-shrink: 0;
    background: var(--color-paper-2, #e8e0ce);
    border-right: 1px solid oklch(0.78 0.02 60);
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 10px 0;
    gap: 4px;
    overflow-y: auto;
  }

  .sidebar-label {
    font-family: "JetBrains Mono", monospace;
    font-size: 8px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--color-ink-soft, #5c5750);
    opacity: 0.5;
    margin: 0 0 6px;
  }

  .node-card {
    width: 56px;
    padding: 8px 4px 6px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 3px;
    border-radius: 4px;
    cursor: grab;
    border: 1px solid transparent;
    transition: background 0.1s, border-color 0.1s;
    user-select: none;
  }

  .node-card:hover {
    background: var(--color-paper, #f4efe3);
    border-color: var(--color-ink-soft, #5c5750);
  }

  .node-card:active { cursor: grabbing; }

  .node-icon {
    font-size: 18px;
    line-height: 1;
  }

  .node-label {
    font-family: "JetBrains Mono", monospace;
    font-size: 8px;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    color: var(--color-ink-soft, #5c5750);
    text-align: center;
  }

  /* Quote picker */
  .picker-backdrop {
    position: fixed;
    inset: 0;
    background: oklch(0.2 0.01 60 / 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 2000;
  }

  .picker-box {
    background: var(--color-paper, #f4efe3);
    border: 1px solid var(--color-paper-2, #e8e0ce);
    border-radius: 4px;
    width: min(520px, 90vw);
    max-height: 70vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .picker-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 14px;
    border-bottom: 1px solid var(--color-paper-2, #e8e0ce);
    flex-shrink: 0;
  }

  .picker-title {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--color-ink-soft, #5c5750);
  }

  .picker-close {
    background: none;
    border: none;
    font-size: 14px;
    color: var(--color-ink-soft, #5c5750);
    cursor: pointer;
    padding: 2px 6px;
  }

  .picker-close:hover { color: var(--color-terracotta, #b8512e); }

  .picker-list {
    overflow-y: auto;
    padding: 8px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .picker-empty {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    color: var(--color-ink-soft, #5c5750);
    text-align: center;
    padding: 24px;
  }

  .picker-item {
    display: flex;
    align-items: baseline;
    gap: 8px;
    padding: 8px 10px;
    background: var(--color-paper-2, #e8e0ce);
    border: 1px solid transparent;
    border-radius: 3px;
    cursor: pointer;
    text-align: left;
    width: 100%;
  }

  .picker-item:hover {
    border-color: var(--color-terracotta, #b8512e);
    background: var(--color-paper, #f4efe3);
  }

  .picker-page {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    color: var(--color-terracotta, #b8512e);
    white-space: nowrap;
    flex-shrink: 0;
  }

  .picker-type {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    white-space: nowrap;
    flex-shrink: 0;
    color: var(--color-ink-soft, #5c5750);
  }

  .picker-type.question { color: #5b7fa6; }
  .picker-type.puzzle { color: #7a5ea6; }

  .picker-text {
    font-family: "Instrument Serif", serif;
    font-size: 12px;
    font-style: italic;
    color: var(--color-ink, #2a2521);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex: 1;
    min-width: 0;
  }
</style>
