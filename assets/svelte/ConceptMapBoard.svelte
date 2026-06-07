<script>
  // ConceptMapBoard — collaborative concept map for a resource (Slice 22).
  //
  // Contract (CLAUDE.md §4.3):
  //   Props from LiveView:
  //     nodes[]          — [{ id, label, position_x, position_y, color, user_id }]
  //     edges[]          — [{ id, source_id, target_id, label }]
  //     current_user_id  — UUID of the signed-in actor
  //
  //   Events to LiveView:
  //     node_created     — { label, position_x, position_y }
  //     node_moved       — { id, position_x, position_y }
  //     node_deleted     — { id }
  //     edge_created     — { source_id, target_id }
  //     edge_deleted     — { id }

  import { SvelteFlow, Controls, Background } from "@xyflow/svelte";
  import "@xyflow/svelte/dist/style.css";
  import { useLiveSvelte } from "live_svelte";

  let { nodes: serverNodes = [], edges: serverEdges = [], current_user_id = null } = $props();

  const { pushEvent } = useLiveSvelte();

  // SvelteFlow state — synced from server props, managed locally during drag.
  let nodes = $state(toFlowNodes(serverNodes));
  let edges = $state(toFlowEdges(serverEdges));
  let draggingId = $state(null);

  // Sync from server props when they change, but skip node sync mid-drag
  // to avoid fighting SvelteFlow's drag position updates.
  $effect(() => {
    if (!draggingId) nodes = toFlowNodes(serverNodes);
  });
  $effect(() => {
    edges = toFlowEdges(serverEdges);
  });

  function toFlowNodes(ns) {
    return ns.map((n) => ({
      id: n.id,
      position: { x: n.position_x, y: n.position_y },
      data: { label: n.label, color: n.color || "default" },
    }));
  }

  function toFlowEdges(es) {
    return es.map((e) => ({
      id: e.id,
      source: e.source_id,
      target: e.target_id,
      ...(e.label ? { label: e.label } : {}),
    }));
  }

  // New node form
  let newLabel = $state("");
  let showForm = $state(false);
  let formInput = $state(null);

  $effect(() => {
    if (showForm && formInput) formInput.focus();
  });

  function submitNewNode(e) {
    e.preventDefault();
    const label = newLabel.trim();
    if (!label) return;
    // Scatter new nodes slightly so they don't pile up
    pushEvent("node_created", {
      label,
      position_x: 80 + Math.random() * 280,
      position_y: 80 + Math.random() * 180,
    });
    newLabel = "";
    showForm = false;
  }

  function onNodeDragStart({ targetNode }) {
    if (targetNode) draggingId = targetNode.id;
  }

  function onNodeDragStop({ targetNode }) {
    draggingId = null;
    if (!targetNode) return;
    pushEvent("node_moved", {
      id: targetNode.id,
      position_x: targetNode.position.x,
      position_y: targetNode.position.y,
    });
  }

  function onConnect(connection) {
    pushEvent("edge_created", {
      source_id: connection.source,
      target_id: connection.target,
    });
  }

  function onDelete({ nodes: dn, edges: de }) {
    for (const n of dn) pushEvent("node_deleted", { id: n.id });
    for (const e of de) pushEvent("edge_deleted", { id: e.id });
  }
</script>

<div class="board-wrap">
  <!-- Toolbar -->
  <div class="board-toolbar">
    {#if showForm}
      <form onsubmit={submitNewNode} class="node-form">
        <input
          bind:this={formInput}
          bind:value={newLabel}
          placeholder="Node label"
          maxlength="200"
          class="node-input"
          onkeydown={(e) => e.key === "Escape" && (showForm = false)}
        />
        <button type="submit" class="btn-add">Add</button>
        <button type="button" class="btn-cancel" onclick={() => (showForm = false)}>
          Cancel
        </button>
      </form>
    {:else}
      <button class="btn-new-node" onclick={() => (showForm = true)}>
        + New node
      </button>
    {/if}
    <span class="hint">
      Connect nodes by dragging from a handle · Delete to remove selected
    </span>
  </div>

  <!-- SvelteFlow canvas -->
  <div class="flow-wrap">
    <SvelteFlow
      bind:nodes
      bind:edges
      fitView
      deleteKey={["Delete", "Backspace"]}
      {onConnect}
      {onDelete}
      onnodedragstart={onNodeDragStart}
      onnodedragstop={onNodeDragStop}
    >
      <Controls />
      <Background />
    </SvelteFlow>
  </div>
</div>

<style>
  .board-wrap {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: var(--color-paper, #f4efe3);
  }

  .board-toolbar {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 16px;
    border-bottom: 1px solid var(--color-paper-2, #e8e0ce);
    background: var(--color-paper, #f4efe3);
    flex-shrink: 0;
  }

  .node-form {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .node-input {
    font-family: "JetBrains Mono", monospace;
    font-size: 12px;
    background: var(--color-paper-2, #e8e0ce);
    border: 1px solid var(--color-ink-soft, #5c5750);
    color: var(--color-ink, #2a2521);
    padding: 4px 10px;
    border-radius: 2px;
    outline: none;
    width: 240px;
  }

  .node-input:focus {
    border-color: var(--color-terracotta, #b8512e);
  }

  .btn-add {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    background: var(--color-terracotta, #b8512e);
    color: var(--color-paper, #f4efe3);
    border: none;
    padding: 4px 12px;
    border-radius: 2px;
    cursor: pointer;
  }

  .btn-cancel,
  .btn-new-node {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    background: none;
    border: 1px solid var(--color-ink-soft, #5c5750);
    color: var(--color-ink-soft, #5c5750);
    padding: 4px 12px;
    border-radius: 2px;
    cursor: pointer;
  }

  .btn-new-node:hover,
  .btn-cancel:hover {
    border-color: var(--color-terracotta, #b8512e);
    color: var(--color-terracotta, #b8512e);
  }

  .hint {
    font-family: "JetBrains Mono", monospace;
    font-size: 10px;
    letter-spacing: 0.04em;
    color: var(--color-ink-soft, #5c5750);
    opacity: 0.6;
    margin-left: auto;
  }

  .flow-wrap {
    flex: 1;
    min-height: 0;

    /* Theme SvelteFlow to match Direction 01 palette */
    --xy-background-color: var(--color-paper, #f4efe3);
    --xy-background-pattern-dots-color: oklch(0.78 0.02 60);
    --xy-node-background-color: var(--color-paper-2, #e8e0ce);
    --xy-node-color: var(--color-ink, #2a2521);
    --xy-node-border: 1px solid var(--color-ink-soft, #5c5750);
    --xy-node-border-radius: 3px;
    --xy-node-boxshadow-hover: none;
    --xy-node-boxshadow-selected: 0 0 0 1.5px var(--color-terracotta, #b8512e);
    --xy-edge-stroke: var(--color-ink-soft, #5c5750);
    --xy-edge-stroke-selected: var(--color-terracotta, #b8512e);
    --xy-handle-background-color: var(--color-terracotta, #b8512e);
    --xy-handle-border-color: var(--color-paper, #f4efe3);
    --xy-selection-background-color: oklch(0.7 0.04 40 / 0.08);
    --xy-selection-border: 1px dotted var(--color-terracotta, #b8512e);
    --xy-controls-button-background-color: var(--color-paper-2, #e8e0ce);
    --xy-controls-button-background-color-hover: var(--color-paper, #f4efe3);
    --xy-controls-button-border-color: var(--color-ink-soft, #5c5750);
    --xy-controls-button-color: var(--color-ink, #2a2521);
    --xy-controls-button-color-hover: var(--color-terracotta, #b8512e);
    --xy-controls-box-shadow: none;
  }

  /* Override node label typography */
  :global(.svelte-flow .svelte-flow__node-default .svelte-flow__node-label),
  :global(.svelte-flow .svelte-flow__node-default) {
    font-family: "JetBrains Mono", monospace;
    font-size: 12px;
    letter-spacing: 0.02em;
    color: var(--color-ink, #2a2521);
    padding: 8px 14px;
  }
</style>
