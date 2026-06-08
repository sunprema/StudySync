<script>
  import { Handle, Position } from "@xyflow/svelte";
  import ReactionBar from "./ReactionBar.svelte";

  let { data, selected } = $props();

  let hovered = $state(false);
  let editing = $state(false);
  let textVal = $state("");

  $effect(() => { textVal = data?.content?.text || ""; });

  function stopEditing(e) {
    e.stopPropagation();
    editing = false;
    data?.onUpdate?.({ text: textVal });
  }
</script>

<div
  class="hot-take-node"
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

  <div class="flame-header">
    <span class="flame-icon">🔥</span>
    <span class="flame-label">Hot Take</span>
  </div>

  <div class="node-inner">
    {#if editing}
      <!-- svelte-ignore a11y_autofocus -->
      <textarea
        class="text-input"
        bind:value={textVal}
        placeholder="I think…"
        autofocus
        rows="4"
        onblur={stopEditing}
      ></textarea>
    {:else}
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <div
        class="text-body"
        class:empty={!textVal}
        onclick={(e) => { e.stopPropagation(); editing = true; }}
        role="button"
        tabindex="0"
        onkeydown={(e) => e.key === "Enter" && (editing = true)}
      >
        {textVal || "I think…"}
      </div>
    {/if}
  </div>

  <ReactionBar reactions={data?.reactions ?? []} onReact={data?.onReact} />
</div>

<style>
  .hot-take-node {
    background: linear-gradient(var(--color-paper, #f4efe3), var(--color-paper, #f4efe3)) padding-box,
                linear-gradient(135deg, #e8450a, #f97316, #fbbf24) border-box;
    border: 2px solid transparent;
    border-radius: 6px;
    width: 220px;
    position: relative;
    cursor: default;
  }

  .hot-take-node.selected {
    background: linear-gradient(var(--color-paper, #f4efe3), var(--color-paper, #f4efe3)) padding-box,
                linear-gradient(135deg, #c93200, #e8450a, #f97316) border-box;
    box-shadow: 0 0 0 1px #f97316;
  }

  .hot-take-node :global(.node-handle) {
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

  .hot-take-node.show-handles :global(.node-handle) { opacity: 1; pointer-events: all; }
  .hot-take-node :global(.node-handle:hover) {
    background: #ffd700 !important;
    border-color: #e8450a !important;
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
    background: oklch(0.97 0.04 55);
    border: 1px solid #f97316;
    border-radius: 2px;
    font-size: 10px;
    color: #c93200;
    cursor: pointer;
    opacity: 0;
    transition: opacity 0.1s;
    padding: 0;
    line-height: 1;
  }

  .hot-take-node.show-handles .delete-btn { opacity: 1; }

  .delete-btn:hover {
    background: #c93200;
    border-color: #c93200;
    color: #fff;
  }

  .flame-header {
    display: flex;
    align-items: center;
    gap: 5px;
    padding: 7px 10px 5px;
    border-bottom: 1px solid oklch(0.88 0.06 55 / 0.5);
    background: linear-gradient(135deg, oklch(0.97 0.04 55), oklch(0.95 0.03 60));
    border-radius: 4px 4px 0 0;
  }

  .flame-icon {
    font-size: 14px;
    line-height: 1;
  }

  .flame-label {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: #c93200;
    font-weight: 700;
  }

  .node-inner {
    padding: 8px 10px 6px;
  }

  .text-body, .text-input {
    font-family: "Instrument Serif", serif;
    font-size: 13px;
    font-style: italic;
    color: var(--color-ink, #2a2521);
    line-height: 1.5;
    width: 100%;
  }

  .text-input {
    background: oklch(0.97 0.03 55);
    border: 1px solid #f97316;
    border-radius: 2px;
    padding: 4px 6px;
    outline: none;
    resize: none;
  }

  .text-body.empty {
    color: var(--color-ink-soft, #5c5750);
    opacity: 0.4;
  }
</style>
