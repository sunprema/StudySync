<script>
  import { SvelteFlow, Controls, Background } from "@xyflow/svelte";
  import "@xyflow/svelte/dist/style.css";
  import { useLiveSvelte, useLiveEvent } from "live_svelte";
  import { onMount, untrack, setContext } from "svelte";
  import * as pdfjsLib from "pdfjs-dist";
  import workerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";

  import PageNode    from "./PageNode.svelte";
  import YoutubeNode from "./YoutubeNode.svelte";
  import TextNode    from "./TextNode.svelte";
  import QuoteNode   from "./QuoteNode.svelte";
  import LinkNode    from "./LinkNode.svelte";
  import HotTakeNode from "./HotTakeNode.svelte";
  import NodeSidebar from "./NodeSidebar.svelte";

  pdfjsLib.GlobalWorkerOptions.workerSrc = workerUrl;

  let {
    nodes: serverNodes = [],
    edges: serverEdges = [],
    current_user_id = null,
    file_url = "",
    total_pages = 0,
    annotations = [],
    workspace_id = "",
    resource_id = "",
  } = $props();

  const { pushEvent } = useLiveSvelte();

  // PDF document — shared to all page nodes via context
  let pdfDoc = $state(null);
  setContext("pdfDoc", { get doc() { return pdfDoc; } });

  onMount(async () => {
    if (!file_url) return;
    try { pdfDoc = await pdfjsLib.getDocument(file_url).promise; } catch (_) {}
  });

  // SvelteFlow state
  let nodes = $state([]);
  let edges = $state([]);
  let draggingId = $state(null);

  $effect(() => {
    const snapshot = toFlowNodes(serverNodes);
    if (untrack(() => !draggingId)) nodes = snapshot;
  });
  $effect(() => { edges = toFlowEdges(serverEdges); });

  const nodeTypes = {
    pageNode:    PageNode,
    youtubeNode: YoutubeNode,
    textNode:    TextNode,
    quoteNode:   QuoteNode,
    linkNode:    LinkNode,
    hotTakeNode: HotTakeNode,
  };

  const typeToFlowType = {
    page:     "pageNode",
    youtube:  "youtubeNode",
    text:     "textNode",
    quote:    "quoteNode",
    link:     "linkNode",
    hot_take: "hotTakeNode",
  };

  function toFlowNodes(ns) {
    return ns.map((n) => ({
      id: n.id,
      type: typeToFlowType[n.node_type] || "pageNode",
      position: { x: n.position_x, y: n.position_y },
      data: buildNodeData(n),
    }));
  }

  function buildNodeData(n) {
    const base = {
      node_type: n.node_type,
      label: n.label,
      user_id: n.user_id,
      reactions: n.reactions || [],
      onReact: (emoji) => pushEvent("toggle_reaction", { node_id: n.id, emoji }),
      onDelete: () => pushEvent("node_deleted", { id: n.id }),
    };
    switch (n.node_type) {
      case "page":
        return { ...base, page_number: n.page_number, onExpand: (p) => { modalPage = p; } };
      case "youtube":
      case "link":
      case "quote":
        return { ...base, content: n.content };
      case "text":
      case "hot_take":
        return { ...base, content: n.content, onUpdate: (c) => updateNodeContent(n.id, c) };
      default:
        return { ...base, content: n.content };
    }
  }

  function toFlowEdges(es) {
    return es.map((e) => ({
      id: e.id,
      source: e.source_id,
      target: e.target_id,
      label: e.label || "",
      labelStyle: "font-size: 14px; cursor: pointer;",
      labelBgStyle: "fill: var(--color-paper-2, #e8e0ce); fill-opacity: 0.85; rx: 2px;",
    }));
  }

  // Node drag within canvas
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
    pushEvent("edge_created", { source_id: connection.source, target_id: connection.target });
  }
  function onDelete({ nodes: dn, edges: de }) {
    for (const n of dn) pushEvent("node_deleted", { id: n.id });
    for (const e of de) pushEvent("edge_deleted", { id: e.id });
  }

  // Text node inline edit — push content update as a node_created+delete or a dedicated update
  function updateNodeContent(id, content) {
    pushEvent("node_content_updated", { id, content });
  }

  // ── Live cursors ──────────────────────────────────────────────────────────
  let peerCursors = $state({});
  const CURSOR_COLORS = ["#b8512e","#5b7fa6","#4a9a7a","#7a5ea6","#e8872a","#2e7ab8","#6a9a4a","#a65e7a"];

  function cursorColor(userId) {
    const hash = [...userId].reduce((a, c) => a + c.charCodeAt(0), 0);
    return CURSOR_COLORS[hash % CURSOR_COLORS.length];
  }

  function cursorName(email) {
    return (email || "?").split("@")[0];
  }

  // Receive peer cursor push events
  useLiveEvent("peer_cursor", (data) => {
    peerCursors = { ...peerCursors, [data.user_id]: { email: data.email, x: data.x, y: data.y, lastSeen: Date.now() } };
  });

  // Clean up stale cursors (> 5s without update)
  $effect(() => {
    const interval = setInterval(() => {
      const now = Date.now();
      const active = Object.fromEntries(Object.entries(peerCursors).filter(([, c]) => now - c.lastSeen < 5000));
      if (Object.keys(active).length !== Object.keys(peerCursors).length) peerCursors = active;
    }, 2000);
    return () => clearInterval(interval);
  });

  // Convert flow coords → position relative to .flow-wrap for cursor overlay
  function flowToCanvasPos(fx, fy) {
    return { x: fx * viewport.zoom + viewport.x, y: fy * viewport.zoom + viewport.y };
  }

  // Throttled mouse move — send cursor position to server
  let _lastCursorSend = 0;
  function onMouseMove(e) {
    const now = Date.now();
    if (now - _lastCursorSend < 80) return;
    _lastCursorSend = now;
    const pos = screenToFlowPos(e.clientX, e.clientY);
    pushEvent("cursor_moved", { x: pos.x, y: pos.y });
  }

  // ── Edge emoji label picker ───────────────────────────────────────────────
  const EDGE_EMOJIS = ["🔗", "⚡", "💡", "❓", "➡️", "🔄", "❌", "✅"];
  let showEdgePicker = $state(false);
  let edgePickerEdgeId = $state(null);
  let edgePickerX = $state(0);
  let edgePickerY = $state(0);

  function onEdgeClick({ detail }) {
    const { edge, event } = detail;
    edgePickerEdgeId = edge.id;
    edgePickerX = event.clientX;
    edgePickerY = event.clientY;
    showEdgePicker = true;
  }

  function pickEdgeEmoji(emoji) {
    if (edgePickerEdgeId) {
      pushEvent("edge_label_updated", { id: edgePickerEdgeId, label: emoji });
    }
    showEdgePicker = false;
    edgePickerEdgeId = null;
  }

  function onCanvasClick(e) {
    if (showEdgePicker && !e.target.closest(".edge-picker")) showEdgePicker = false;
  }

  // ── Drag from sidebar onto canvas ──────────────────────────────────────────

  // Track viewport so we can convert screen → flow coordinates on drop
  let viewport = $state({ x: 0, y: 0, zoom: 1 });
  let flowContainer = $state(null);
  let sidebarRef = $state(null);

  function screenToFlowPos(screenX, screenY) {
    const rect = flowContainer?.getBoundingClientRect() ?? { left: 0, top: 0 };
    return {
      x: (screenX - rect.left - viewport.x) / viewport.zoom,
      y: (screenY - rect.top - viewport.y) / viewport.zoom,
    };
  }

  // Config forms after drop
  let showYoutubeForm = $state(false);
  let showPageForm    = $state(false);
  let showLinkForm    = $state(false);
  let dropPos = $state({ x: 200, y: 200 });

  let youtubeUrlInput = $state("");
  let youtubeTitleInput = $state("");
  let pageNumberInput = $state("");
  let linkUrlInput = $state("");
  let linkTitleInput = $state("");
  let pageError = $state("");

  function onDragOver(e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = "copy";
  }

  function onDrop(e) {
    e.preventDefault();
    const nodeType = e.dataTransfer.getData("application/board-node-type");
    if (!nodeType) return;

    const flowPos = screenToFlowPos(e.clientX, e.clientY);
    dropPos = flowPos;

    if (nodeType === "quote") {
      sidebarRef?.openQuotePicker(flowPos);
    } else if (nodeType === "page") {
      showPageForm = true;
    } else if (nodeType === "youtube") {
      showYoutubeForm = true;
      youtubeUrlInput = "";
      youtubeTitleInput = "";
    } else if (nodeType === "link") {
      showLinkForm = true;
      linkUrlInput = "";
      linkTitleInput = "";
    } else if (nodeType === "text") {
      pushEvent("node_created", {
        node_type: "text",
        position_x: flowPos.x,
        position_y: flowPos.y,
        content: { heading: "", body: "" },
      });
    } else if (nodeType === "hot_take") {
      pushEvent("node_created", {
        node_type: "hot_take",
        position_x: flowPos.x,
        position_y: flowPos.y,
        content: { text: "" },
      });
    }
  }

  function submitYoutube(e) {
    e.preventDefault();
    if (!youtubeUrlInput.trim()) return;
    const m = youtubeUrlInput.match(/(?:v=|youtu\.be\/|embed\/)([A-Za-z0-9_-]{11})/);
    const video_id = m ? m[1] : null;
    pushEvent("node_created", {
      node_type: "youtube",
      position_x: dropPos.x,
      position_y: dropPos.y,
      content: { url: youtubeUrlInput.trim(), video_id, title: youtubeTitleInput.trim() || youtubeUrlInput.trim() },
    });
    showYoutubeForm = false;
  }

  function submitPage(e) {
    e.preventDefault();
    const page = parseInt(pageNumberInput, 10);
    if (!page || page < 1) { pageError = "Enter a valid page number"; return; }
    if (total_pages && page > total_pages) { pageError = `Max page is ${total_pages}`; return; }
    pageError = "";
    pushEvent("node_created", {
      node_type: "page",
      page_number: page,
      position_x: dropPos.x,
      position_y: dropPos.y,
    });
    pageNumberInput = "";
    showPageForm = false;
  }

  function submitLink(e) {
    e.preventDefault();
    if (!linkUrlInput.trim()) return;
    let url = linkUrlInput.trim();
    if (!url.startsWith("http")) url = "https://" + url;
    pushEvent("node_created", {
      node_type: "link",
      position_x: dropPos.x,
      position_y: dropPos.y,
      content: { url, title: linkTitleInput.trim() || url },
    });
    showLinkForm = false;
  }

  function handleQuotePicked({ detail }) {
    const { pos, annotation } = detail;
    pushEvent("node_created", {
      node_type: "quote",
      position_x: pos.x,
      position_y: pos.y,
      content: {
        text: annotation.text,
        page_number: annotation.page_number,
        annotation_id: annotation.id,
        type: annotation.type,
      },
    });
  }

  // Page thumbnail modal
  let modalPage = $state(null);
  let modalCanvas = $state(null);

  const readerBase = $derived(
    workspace_id && resource_id
      ? `/workspaces/${workspace_id}/library/${resource_id}`
      : null
  );

  $effect(() => {
    if (modalPage && modalCanvas && pdfDoc) renderPageToCanvas(pdfDoc, modalPage, modalCanvas, 700);
  });

  async function renderPageToCanvas(doc, pageNum, canvas, targetWidth) {
    try {
      const page = await doc.getPage(pageNum);
      const vp = page.getViewport({ scale: 1 });
      const scaled = page.getViewport({ scale: targetWidth / vp.width });
      canvas.width = scaled.width;
      canvas.height = scaled.height;
      await page.render({ canvasContext: canvas.getContext("2d"), viewport: scaled }).promise;
    } catch (_) {}
  }
</script>

<div class="board-root">
  <!-- Sidebar palette -->
  <NodeSidebar
    bind:this={sidebarRef}
    {annotations}
    on:quotePicked={handleQuotePicked}
  />

  <!-- Flow canvas -->
  <div
    class="flow-wrap"
    bind:this={flowContainer}
    ondragover={onDragOver}
    ondrop={onDrop}
    onmousemove={onMouseMove}
    onclick={onCanvasClick}
    role="region"
    aria-label="Concept map canvas"
  >
    <SvelteFlow
      bind:nodes
      bind:edges
      bind:viewport
      {nodeTypes}
      fitView
      connectionMode="loose"
      deleteKey={["Delete", "Backspace"]}
      {onConnect}
      {onDelete}
      onnodedragstart={onNodeDragStart}
      onnodedragstop={onNodeDragStop}
      onedgeclick={onEdgeClick}
    >
      <Controls />
      <Background />
    </SvelteFlow>

    <!-- Live cursor overlay -->
    <div class="cursor-overlay" aria-hidden="true">
      {#each Object.entries(peerCursors) as [userId, cursor]}
        {@const pos = flowToCanvasPos(cursor.x, cursor.y)}
        {@const color = cursorColor(userId)}
        <div class="peer-cursor" style="left:{pos.x}px; top:{pos.y}px; --c:{color}">
          <svg class="cursor-svg" viewBox="0 0 12 16" width="12" height="16">
            <path d="M0 0 L0 14 L4 10 L8 16 L9.5 15 L5.5 9 L10 9 Z" fill="{color}" stroke="white" stroke-width="0.8"/>
          </svg>
          <span class="cursor-label">{cursorName(cursor.email)}</span>
        </div>
      {/each}
    </div>
  </div>
</div>

<!-- ── Config forms (shown after dropping a node) ────────────────────────── -->

{#if showPageForm}
  <div class="form-overlay" role="dialog" aria-modal="true" aria-label="Add page node">
    <form class="config-form" onsubmit={submitPage}>
      <p class="form-title">Add page node</p>
      <label class="form-label" for="drop-page-input">Page number</label>
      <input
        id="drop-page-input"
        type="number"
        min="1"
        max={total_pages || undefined}
        placeholder={total_pages ? `1 – ${total_pages}` : "page number"}
        class="form-input"
        bind:value={pageNumberInput}
       
      />
      {#if pageError}<span class="form-error">{pageError}</span>{/if}
      <div class="form-actions">
        <button type="submit" class="btn-primary">Add</button>
        <button type="button" class="btn-ghost" onclick={() => { showPageForm = false; pageError = ""; }}>Cancel</button>
      </div>
    </form>
  </div>
{/if}

{#if showYoutubeForm}
  <div class="form-overlay" role="dialog" aria-modal="true" aria-label="Add YouTube node">
    <form class="config-form" onsubmit={submitYoutube}>
      <p class="form-title">Add YouTube video</p>
      <label class="form-label" for="yt-url-input">YouTube URL</label>
      <input id="yt-url-input" type="url" placeholder="https://youtube.com/watch?v=…" class="form-input" bind:value={youtubeUrlInput} />
      <label class="form-label" for="yt-title-input">Title (optional)</label>
      <input id="yt-title-input" type="text" placeholder="Video title" class="form-input" bind:value={youtubeTitleInput} />
      <div class="form-actions">
        <button type="submit" class="btn-primary">Add</button>
        <button type="button" class="btn-ghost" onclick={() => (showYoutubeForm = false)}>Cancel</button>
      </div>
    </form>
  </div>
{/if}

{#if showLinkForm}
  <div class="form-overlay" role="dialog" aria-modal="true" aria-label="Add link node">
    <form class="config-form" onsubmit={submitLink}>
      <p class="form-title">Add web link</p>
      <label class="form-label" for="link-url-input">URL</label>
      <input id="link-url-input" type="text" placeholder="https://…" class="form-input" bind:value={linkUrlInput} />
      <label class="form-label" for="link-title-input">Title (optional)</label>
      <input id="link-title-input" type="text" placeholder="Page title" class="form-input" bind:value={linkTitleInput} />
      <div class="form-actions">
        <button type="submit" class="btn-primary">Add</button>
        <button type="button" class="btn-ghost" onclick={() => (showLinkForm = false)}>Cancel</button>
      </div>
    </form>
  </div>
{/if}

{#if showEdgePicker}
  <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
  <div class="edge-picker" style="left:{edgePickerX}px; top:{edgePickerY}px;" role="menu">
    {#each EDGE_EMOJIS as emoji}
      <button class="edge-emoji-btn" onclick={() => pickEdgeEmoji(emoji)} title={emoji}>{emoji}</button>
    {/each}
    <button class="edge-emoji-clear" onclick={() => pickEdgeEmoji("")} title="Remove label">✕</button>
  </div>
{/if}

<!-- Page thumbnail modal -->
{#if modalPage !== null}
  <div
    class="modal-backdrop"
    onclick={(e) => { if (e.target === e.currentTarget) modalPage = null; }}
    onkeydown={(e) => e.key === "Escape" && (modalPage = null)}
    role="dialog"
    aria-modal="true"
    aria-label="Page {modalPage} preview"
    tabindex="-1"
  >
    <div class="modal-box">
      <div class="modal-header">
        <span class="modal-title">Page {modalPage}</span>
        <div class="modal-actions">
          {#if readerBase}
            <a href="{readerBase}?page={modalPage}" class="reader-link">→ Open in Reader</a>
          {/if}
          <button class="modal-close" onclick={() => (modalPage = null)}>✕</button>
        </div>
      </div>
      <div class="modal-body">
        {#if pdfDoc}
          <canvas bind:this={modalCanvas} class="modal-canvas"></canvas>
        {:else}
          <p class="modal-loading">Loading PDF…</p>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .board-root {
    display: flex;
    height: 100%;
    overflow: hidden;
  }

  .flow-wrap {
    flex: 1;
    min-width: 0;

    --xy-background-color: var(--color-paper, #f4efe3);
    --xy-background-pattern-dots-color: oklch(0.78 0.02 60);
    --xy-node-background-color: transparent;
    --xy-node-border: none;
    --xy-node-boxshadow-hover: none;
    --xy-node-boxshadow-selected: none;
    --xy-edge-stroke: var(--color-ink-soft, #5c5750);
    --xy-edge-stroke-selected: var(--color-terracotta, #b8512e);
    --xy-handle-background-color: #f5c518;
    --xy-handle-border-color: #c49a00;
    --xy-selection-background-color: oklch(0.7 0.04 40 / 0.08);
    --xy-selection-border: 1px dotted var(--color-terracotta, #b8512e);
    --xy-controls-button-background-color: var(--color-paper-2, #e8e0ce);
    --xy-controls-button-background-color-hover: var(--color-paper, #f4efe3);
    --xy-controls-button-border-color: var(--color-ink-soft, #5c5750);
    --xy-controls-button-color: var(--color-ink, #2a2521);
    --xy-controls-button-color-hover: var(--color-terracotta, #b8512e);
    --xy-controls-box-shadow: none;
  }

  /* ── Live cursor overlay ──────────────────────────────────────────────── */
  .cursor-overlay {
    position: absolute;
    inset: 0;
    pointer-events: none;
    overflow: hidden;
    z-index: 5;
  }

  .peer-cursor {
    position: absolute;
    display: flex;
    align-items: flex-start;
    gap: 4px;
    transform: translate(0, 0);
    transition: left 0.08s linear, top 0.08s linear;
  }

  .cursor-svg { flex-shrink: 0; }

  .cursor-label {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    background: var(--c);
    color: #fff;
    padding: 1px 5px;
    border-radius: 2px;
    white-space: nowrap;
    margin-top: 12px;
  }

  /* ── Edge emoji label picker ──────────────────────────────────────────── */
  .edge-picker {
    position: fixed;
    background: var(--color-paper, #f4efe3);
    border: 1px solid var(--color-paper-2, #e8e0ce);
    border-radius: 4px;
    padding: 4px 6px;
    display: flex;
    align-items: center;
    gap: 2px;
    z-index: 2000;
    box-shadow: 0 2px 8px oklch(0.2 0.01 60 / 0.15);
    transform: translate(-50%, -110%);
  }

  .edge-emoji-btn {
    font-size: 16px;
    padding: 4px;
    background: none;
    border: 1px solid transparent;
    border-radius: 3px;
    cursor: pointer;
    transition: background 0.1s;
  }

  .edge-emoji-btn:hover {
    background: var(--color-paper-2, #e8e0ce);
    border-color: var(--color-ink-soft, #5c5750);
  }

  .edge-emoji-clear {
    font-family: "JetBrains Mono", monospace;
    font-size: 10px;
    color: var(--color-ink-soft, #5c5750);
    padding: 3px 6px;
    background: none;
    border: 1px solid var(--color-paper-2, #e8e0ce);
    border-radius: 2px;
    cursor: pointer;
    margin-left: 4px;
  }

  .edge-emoji-clear:hover { color: var(--color-terracotta, #b8512e); }

  /* ── Config forms ─────────────────────────────────────────────────────── */
  .form-overlay {
    position: fixed;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1500;
    background: oklch(0.2 0.01 60 / 0.35);
  }

  .config-form {
    background: var(--color-paper, #f4efe3);
    border: 1px solid var(--color-paper-2, #e8e0ce);
    border-radius: 4px;
    padding: 20px 24px;
    width: min(360px, 90vw);
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .form-title {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--color-ink-soft, #5c5750);
    margin: 0 0 4px;
  }

  .form-label {
    font-family: "JetBrains Mono", monospace;
    font-size: 10px;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    color: var(--color-ink-soft, #5c5750);
  }

  .form-input {
    font-family: "JetBrains Mono", monospace;
    font-size: 12px;
    background: var(--color-paper-2, #e8e0ce);
    border: 1px solid var(--color-ink-soft, #5c5750);
    color: var(--color-ink, #2a2521);
    padding: 6px 10px;
    border-radius: 2px;
    outline: none;
    width: 100%;
  }

  .form-input:focus { border-color: var(--color-terracotta, #b8512e); }

  .form-error {
    font-family: "JetBrains Mono", monospace;
    font-size: 10px;
    color: var(--color-terracotta, #b8512e);
  }

  .form-actions {
    display: flex;
    gap: 8px;
    margin-top: 4px;
  }

  .btn-primary {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    background: var(--color-terracotta, #b8512e);
    color: var(--color-paper, #f4efe3);
    border: none;
    padding: 6px 14px;
    border-radius: 2px;
    cursor: pointer;
  }

  .btn-ghost {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    background: none;
    border: 1px solid var(--color-ink-soft, #5c5750);
    color: var(--color-ink-soft, #5c5750);
    padding: 6px 14px;
    border-radius: 2px;
    cursor: pointer;
  }

  .btn-ghost:hover {
    border-color: var(--color-terracotta, #b8512e);
    color: var(--color-terracotta, #b8512e);
  }

  /* ── Page modal ───────────────────────────────────────────────────────── */
  .modal-backdrop {
    position: fixed;
    inset: 0;
    background: oklch(0.2 0.01 60 / 0.55);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
  }

  .modal-box {
    background: var(--color-paper, #f4efe3);
    border: 1px solid var(--color-paper-2, #e8e0ce);
    border-radius: 4px;
    max-width: 780px;
    max-height: 90vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 16px;
    border-bottom: 1px solid var(--color-paper-2, #e8e0ce);
    flex-shrink: 0;
  }

  .modal-actions {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .reader-link {
    font-family: "JetBrains Mono", monospace;
    font-size: 10px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--color-terracotta, #b8512e);
    text-decoration: none;
    padding: 3px 8px;
    border: 1px solid var(--color-terracotta, #b8512e);
    border-radius: 2px;
    transition: background 0.1s;
  }

  .reader-link:hover {
    background: var(--color-terracotta, #b8512e);
    color: var(--color-paper, #f4efe3);
  }

  .modal-title {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--color-ink-soft, #5c5750);
  }

  .modal-close {
    font-size: 14px;
    color: var(--color-ink-soft, #5c5750);
    background: none;
    border: none;
    cursor: pointer;
    padding: 2px 6px;
    border-radius: 2px;
  }

  .modal-close:hover { color: var(--color-terracotta, #b8512e); }

  .modal-body { overflow-y: auto; padding: 16px; }

  .modal-canvas {
    display: block;
    max-width: 100%;
    border: 1px solid var(--color-paper-2, #e8e0ce);
  }

  .modal-loading {
    font-family: "JetBrains Mono", monospace;
    font-size: 11px;
    color: var(--color-ink-soft, #5c5750);
    text-align: center;
    padding: 40px;
  }
</style>
