<script>
  import { Handle, Position } from "@xyflow/svelte";

  let { data, selected } = $props();

  let hovered = $state(false);
  let editingHeading = $state(false);
  let editingBody = $state(false);
  let headingVal = $state("");
  let bodyVal = $state("");

  // Sync from server prop changes
  $effect(() => { headingVal = data?.content?.heading || ""; });
  $effect(() => { bodyVal = data?.content?.body || ""; });

  function stopEditing(e) {
    e.stopPropagation();
    editingHeading = false;
    editingBody = false;
    data?.onUpdate?.({ heading: headingVal, body: bodyVal });
  }
</script>

<div
  class="text-node"
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

  <div class="node-inner">
    <!-- Heading -->
    {#if editingHeading}
      <!-- svelte-ignore a11y_autofocus -->
      <input
        class="heading-input"
        bind:value={headingVal}
        placeholder="Heading…"
        autofocus
        onblur={stopEditing}
        onkeydown={(e) => e.key === "Enter" && stopEditing(e)}
      />
    {:else}
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <div
        class="heading"
        class:empty={!headingVal}
        onclick={(e) => { e.stopPropagation(); editingHeading = true; }}
        role="button"
        tabindex="0"
        onkeydown={(e) => e.key === "Enter" && (editingHeading = true)}
      >
        {headingVal || "Click to add heading"}
      </div>
    {/if}

    <!-- Body -->
    {#if editingBody}
      <!-- svelte-ignore a11y_autofocus -->
      <textarea
        class="body-input"
        bind:value={bodyVal}
        placeholder="Write a concept, argument, or note…"
        autofocus
        rows="4"
        onblur={stopEditing}
      ></textarea>
    {:else}
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <div
        class="body"
        class:empty={!bodyVal}
        onclick={(e) => { e.stopPropagation(); editingBody = true; }}
        role="button"
        tabindex="0"
        onkeydown={(e) => e.key === "Enter" && (editingBody = true)}
      >
        {bodyVal || "Double-click to write…"}
      </div>
    {/if}
  </div>

  <div class="node-badge-row">
    <span class="type-badge">Concept</span>
  </div>
</div>

<style>
  .text-node {
    background: var(--color-paper, #f4efe3);
    border: 1.5px solid var(--color-ink-soft, #5c5750);
    border-radius: 4px;
    width: 220px;
    position: relative;
    cursor: default;
  }

  .text-node.selected {
    border-color: var(--color-terracotta, #b8512e);
    box-shadow: 0 0 0 2px var(--color-terracotta, #b8512e);
  }

  .text-node :global(.node-handle) {
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

  .text-node.show-handles :global(.node-handle) { opacity: 1; pointer-events: all; }
  .text-node :global(.node-handle:hover) {
    background: #ffd700 !important;
    border-color: #b8512e !important;
  }

  .node-inner {
    padding: 10px 12px 6px;
  }

  .heading, .heading-input {
    font-family: "Instrument Serif", serif;
    font-size: 14px;
    color: var(--color-ink, #2a2521);
    width: 100%;
    margin-bottom: 6px;
    font-weight: 600;
  }

  .heading-input {
    background: var(--color-paper-2, #e8e0ce);
    border: 1px solid var(--color-terracotta, #b8512e);
    border-radius: 2px;
    padding: 2px 6px;
    outline: none;
  }

  .heading.empty { color: var(--color-ink-soft, #5c5750); opacity: 0.4; font-style: italic; }

  .body, .body-input {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    color: var(--color-ink, #2a2521);
    line-height: 1.5;
    width: 100%;
  }

  .body-input {
    background: var(--color-paper-2, #e8e0ce);
    border: 1px solid var(--color-terracotta, #b8512e);
    border-radius: 2px;
    padding: 4px 6px;
    outline: none;
    resize: none;
  }

  .body.empty { color: var(--color-ink-soft, #5c5750); opacity: 0.35; font-style: italic; }

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
