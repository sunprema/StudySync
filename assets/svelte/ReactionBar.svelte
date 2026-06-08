<script>
  let { reactions = [], onReact } = $props();

  const EMOJIS = ["🔥", "💡", "😮", "🤔", "✅"];

  const reactionMap = $derived(
    Object.fromEntries(reactions.map((r) => [r.emoji, r]))
  );
</script>

<div class="reaction-bar" role="group" aria-label="Reactions">
  {#each EMOJIS as emoji}
    {@const r = reactionMap[emoji]}
    <button
      class="reaction-btn"
      class:active={r?.reacted_by_me}
      onclick={(e) => { e.stopPropagation(); onReact?.(emoji); }}
      title={r?.count ? `${r.count} reaction${r.count > 1 ? "s" : ""}` : emoji}
    >
      <span class="emoji">{emoji}</span>
      {#if r?.count}
        <span class="count">{r.count}</span>
      {/if}
    </button>
  {/each}
</div>

<style>
  .reaction-bar {
    display: flex;
    align-items: center;
    gap: 2px;
    padding: 4px 8px 5px;
    border-top: 1px solid var(--color-paper-2, #e8e0ce);
    flex-wrap: wrap;
  }

  .reaction-btn {
    display: flex;
    align-items: center;
    gap: 2px;
    padding: 2px 5px;
    background: transparent;
    border: 1px solid transparent;
    border-radius: 10px;
    cursor: pointer;
    transition: background 0.1s, border-color 0.1s;
    line-height: 1;
  }

  .reaction-btn:hover {
    background: var(--color-paper-2, #e8e0ce);
    border-color: var(--color-ink-soft, #5c5750);
  }

  .reaction-btn.active {
    background: oklch(0.85 0.04 40 / 0.5);
    border-color: var(--color-terracotta, #b8512e);
  }

  .emoji { font-size: 13px; line-height: 1; }

  .count {
    font-family: "JetBrains Mono", monospace;
    font-size: 9px;
    font-weight: 600;
    color: var(--color-ink-soft, #5c5750);
    min-width: 10px;
  }

  .reaction-btn.active .count { color: var(--color-terracotta, #b8512e); }
</style>
