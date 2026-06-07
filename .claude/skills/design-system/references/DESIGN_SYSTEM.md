# Design System

A handoff document for Claude coding agents (and humans) building new screens.

**Source of truth:** the files in this project. This document summarises and explains; when in doubt, read the CSS.

Even though we have reference to JSX in this file, we are not a React application. Ours is a Elixir, Phoenix liveview application.

| Concern                                                       | File                                     |
| ------------------------------------------------------------- | ---------------------------------------- |
| Tokens (colors, type, spacing, status palette, density)       | [`styles.css`](./styles.css)             |
| Triage / detail / logic inspector styles                      | [`nurse.css`](./nurse.css)               |
| Protocol builder styles                                       | [`protocol.css`](./protocol.css)         |
| Patient call screen styles                                    | [`patient.css`](./patient.css)           |
| Shared React primitives (icons, pills, brand mark, sparkline) | [`shared.jsx`](./shared.jsx)             |
| Tweaks panel + form controls                                  | [`tweaks-panel.jsx`](./tweaks-panel.jsx) |
| Mock clinical data                                            | [`data.js`](./data.js)                   |

---

## 1 · Product principles

PostOpGuard sits between a recovering patient and the clinical team. The product is judged on **trust**, not flash.

1. **Trust over flash.** Stripe-clean, hospital-EMR clarity. No gradient backgrounds, no decorative shadows, no flashy motion. Use the brand gradient only on the brand mark.
2. **Glass box for decisions.** The LLM transcribes; **Lua decides**. Any alert UI must let a clinician see exactly which protocol fired and which inputs drove the score. Never blame "AI" — name the protocol and show the trace.
3. **Calm under load.** Stoplight colors are reserved for clinical state. Avoid alarm fatigue: red is for "page the on-call now", amber is for "watch this", green is "no action needed". Use the soft palette for ambient/long-lived surfaces.
4. **Audio is a first-class clinical object.** When a check-in is shown, the original audio (waveform, prosody, timestamped markers) leads. The transcript is supporting.
5. **Voice-first patient surfaces.** Single primary action per screen. Tap targets ≥ 44px. Status orb conveys system phase (listening / processing / responding) before words.
6. **Every machine action is provenance-tagged.** Events display _who_ did them: `Oban` (job runner), `LLM` (transcription/extraction), `Lua` (decision), `System`. See [audit tags](#audit-tags).

---

## 2 · Tokens

All tokens live in `styles.css` as CSS custom properties on `:root`. **Always reference tokens, never hardcode values.**

### 2.1 Color

**Neutrals (cool-tinted whites and charcoal)**

| Token           | Value (light)          | Use                                 |
| --------------- | ---------------------- | ----------------------------------- |
| `--bg`          | `oklch(98% 0.004 200)` | App background                      |
| `--surface`     | `#ffffff`              | Cards, top bar, sidebars            |
| `--surface-2`   | `oklch(97% 0.005 210)` | Hover, search input, audit pane bg  |
| `--surface-3`   | `oklch(95% 0.006 215)` | Active state, selected row          |
| `--ink`         | `oklch(22% 0.012 240)` | Primary text                        |
| `--ink-2`       | `oklch(38% 0.012 240)` | Secondary text                      |
| `--muted`       | `oklch(54% 0.012 240)` | Tertiary text, labels               |
| `--faint`       | `oklch(72% 0.010 240)` | Disabled / dividers                 |
| `--line`        | `oklch(92% 0.006 220)` | Default border                      |
| `--line-strong` | `oklch(86% 0.008 220)` | Emphasised border (selected, focus) |

**Accent — sage-teal**

| Token           | Use                                                               |
| --------------- | ----------------------------------------------------------------- |
| `--accent`      | Brand accent (system voice, extracted values, primary highlights) |
| `--accent-2`    | Slightly lighter accent (hover)                                   |
| `--accent-tint` | Accent background fill                                            |
| `--accent-edge` | Accent border                                                     |

**Stoplight (traditional, default)**

Triggered by `[data-tone="soft"]` on `<html>` for the desaturated alternative.

| State      | Color token  | Tint              | Edge              | Meaning                               |
| ---------- | ------------ | ----------------- | ----------------- | ------------------------------------- |
| `critical` | `--critical` | `--critical-tint` | `--critical-edge` | Page on-call now. Confirmed red-flag. |
| `warning`  | `--warning`  | `--warning-tint`  | `--warning-edge`  | Watch this. Trending toward critical. |
| `stable`   | `--stable`   | `--stable-tint`   | `--stable-edge`   | No action. On track.                  |
| (pending)  | `--muted`    | `--surface-2`     | `--line`          | Awaiting data (missed check-in).      |

### 2.2 Brand gradient

Used **only** on the brand mark and wordmark. Never on backgrounds, never as a decoration on charts.

```css
/* shield mark (top-left → bottom-right) */
linear-gradient(135deg, #3387C7 0%, #3FB0A8 55%, #7BC58A 100%);

/* wordmark (left → right) — slightly deeper for legibility on white */
linear-gradient(90deg, #1F5B8F 0%, #2E8A8B 55%, #3FA372 100%);
```

Render via the `<BrandMark>` + `<BrandWordmark>` React components in `shared.jsx`. **Do not redraw the shield** — import the component.

### 2.3 Typography

Two families, no exceptions:

- **`IBM Plex Sans`** — all UI. Weights 400 / 500 / 600 / 700.
- **`IBM Plex Mono`** — data, code, audit trails, timestamps, IDs (MRN, protocol IDs), audio markers, token names.

Loaded from Google Fonts in `PostOpGuard.html`. Apply via `var(--font-sans)` and `var(--font-mono)`.

**Type scale (concrete, in use)**

| Use                       | Size             | Weight     | Letter-spacing               |
| ------------------------- | ---------------- | ---------- | ---------------------------- |
| Page title (h1)           | 24–26px          | 600        | `-0.02em`                    |
| Patient name              | 26px             | 600        | `-0.02em`                    |
| Card title / `.card-head` | 13–14px          | 500        | —                            |
| Body / row                | 13–14px          | 400–500    | —                            |
| Big metric                | 24px             | 600 (mono) | `-0.02em`                    |
| Vital value               | 22px             | 600        | `-0.01em`                    |
| Sim score                 | 36px             | 600 (mono) | `-0.02em`                    |
| `.section-label`          | 10.5–11px (mono) | 500        | `0.06–0.08em`, **uppercase** |
| `.mono-tag`               | 10.5px (mono)    | 400        | —                            |
| Trigger / sub copy        | 12px             | 400        | —                            |
| Caption / timestamp       | 10.5–11px (mono) | 400        | —                            |

**Rules**

- Body sizes scale with the density tweak (`--base-fs`, `--label-fs`). Never inline-set body sizes; consume the variable.
- Numbers use `font-variant-numeric: tabular-nums` whenever they sit in a column or update live (vital values, sim score, trace weights).
- All-caps text **must** have `letter-spacing` ≥ 0.04em and is **always** mono.
- `text-wrap: pretty` on long display headings; `text-wrap: balance` on patient-facing prompts (`.ps-cue`, `.ps-sub`).

### 2.4 Spacing & radius

There is no global numeric scale — sizes are CSS-variable-driven so the **Density** tweak can shift them. Cards consume `--card-pad`, rows consume `--row-py` / `--row-px`, etc.

When you need to reach for a value not in a variable, snap to **4 / 6 / 8 / 10 / 12 / 14 / 16 / 18 / 22 / 28 / 60 px**.

| Radius | Use                      |
| ------ | ------------------------ |
| 4px    | Mono tags, ext-bar       |
| 5–6px  | Buttons, small chips     |
| 6–7px  | Inputs, sort buttons     |
| 8–10px | Cards, prosody cards     |
| 999px  | Pills, user chip, ps-btn |

### 2.5 Density

The Density tweak swaps these variables on `<html data-density="compact">`:

| Var          | Comfortable | Compact |
| ------------ | ----------- | ------- |
| `--row-py`   | 14          | 8       |
| `--row-px`   | 18          | 14      |
| `--cell-gap` | 16          | 10      |
| `--card-pad` | 22          | 16      |
| `--base-fs`  | 14          | 13      |
| `--label-fs` | 11          | 10      |

New screens must honour these variables so they switch density correctly.

### 2.6 Alert tone

`<html data-tone="soft">` reduces saturation on `--critical` / `--warning` / `--stable` for less alarming environments (default tone is `traditional`). Always use tokens, never the soft-tone values directly.

---

## 3 · Layout & app shell

```
┌───────────────────────────────────────────────────────────┐
│ TopBar (h:56, sticky)                                     │  brand · nav · status · user
├──────────┬────────────────────────────────────────────────┤
│ Queue    │ Detail / page content                          │
│ (380px)  │                                                │
│ scroll   │ scroll                                         │
└──────────┴────────────────────────────────────────────────┘
```

**Rules**

- Minimum app width: `1280px`. Use the print HTML when you need a smaller form factor.
- Sticky top bar (`.topbar`, h:56). Brand left, nav center-left, status + user right. **Never** put primary actions in the top bar — they live in card headers and page heads.
- Two-pane layouts use a fixed-width left column (queue / sidebar: 280–380px) and a scrolling main pane.
- Page content uses `padding: 22–28px` with `max-width: 1280px` for the inner column.

---

## 4 · Components

### 4.1 React primitives (import from `shared.jsx`) just a reference.

Just a reference, we should create Phoenix components not react

| Component                            | Signature                                                       | Notes                                                                                                                                                                                                                                |
| ------------------------------------ | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `<Icon.X size?>`                     | Lightweight inline SVGs                                         | Heart, Drop, Pill, Thermo, Mic, Phone, Bell, Search, ArrowUp/Down/Dash, Play, Check, X, Lock, Sparkle, Wave, Bolt, Stack. `stroke="currentColor"` so colour comes from text colour. **Do not add new icons inline** — extend `Icon`. |
| `<StatusPill status children? dot?>` | `status` ∈ `critical \| warning \| stable \| pending \| accent` | Self-labels (`Critical`, `Trending`, `Stable`, `Awaiting`) unless you pass children.                                                                                                                                                 |
| `<Trend dir>`                        | `dir` ∈ `up \| down \| flat`                                    | Red up-arrow, green down-arrow, muted dash. Trend interpretation is clinical — up is bad.                                                                                                                                            |
| `<Sparkline values color w h>`       | tiny inline trend                                               | Polyline only. Don't add fills or labels.                                                                                                                                                                                            |
| `<BrandMark size>`                   | the shield mark                                                 | Inline SVG, gradient ID-scoped via `useId` so multiple instances coexist.                                                                                                                                                            |
| `<BrandWordmark size>`               | gradient "PostOpGuard" text                                     | Use next to `<BrandMark>` in the top bar.                                                                                                                                                                                            |

### 4.2 Pills

`.pill` is the universal small-state primitive. Status maps to a colour class, with an optional `.pill-dot` inside.

```html
<span class="pill critical"><span class="pill-dot"></span>Critical</span>
<span class="pill stable"><span class="pill-dot"></span>On schedule</span>
<span class="pill muted"><span class="pill-dot"></span>Awaiting</span>
<span class="pill accent"><span class="pill-dot"></span>DVT_Risk_Hip_v2</span>
```

11px mono, uppercase, 0.04em letter-spacing, pill-shaped. **Never** put body-cased text in a `.pill`. For lowercase metadata, use `.mono-tag` instead.

### 4.3 Buttons

```html
<button class="btn">Default</button>
<button class="btn btn-primary">Primary (ink fill)</button>
<button class="btn btn-danger">Danger (critical fill)</button>
<button class="btn btn-ghost">Ghost</button>
<button class="btn btn-sm">Small</button>
```

**Rules**

- Maximum **one** `btn-primary` per card / page section. The primary action on the patient detail head is **Call patient**. Within an alert, it's **Page on-call**.
- `btn-danger` is reserved for irreversible clinical pages (page on-call, escalate).
- Pair button + icon with `gap: 6–8px`. Icons sit left.
- Hover only changes background; no scale, no shadow.

### 4.4 Cards

```html
<section class="card">
  <header class="card-head">
    <div>
      <div class="section-label">Vitals · self-reported</div>
      <!-- optional sub line -->
    </div>
    <span class="mono-tag">updated 08:42</span>
  </header>
  <!-- body: tiles, grids, lists -->
</section>
```

- 1px `--line` border, 10px radius, `--surface` fill.
- `.card-head` provides the title row. Title-row right column is for **metadata** (mono-tags), not primary actions. If the card needs an action, use `.btn-ghost btn-sm`.
- Card body has no padding by default — the contents (grids, vital tiles, transcript) define their own padding so cells can sit edge-to-edge against borders.

### 4.5 Status pill anatomy (StatusPill props)

| Prop          | Effect                                                                       |
| ------------- | ---------------------------------------------------------------------------- |
| `status`      | Color class + default label                                                  |
| `children`    | Override label (e.g. `<StatusPill status="critical">Missed AM</StatusPill>`) |
| `dot={false}` | Hide the leading dot                                                         |

### 4.6 Audit tags

Provenance-tagged event log. Color code by source:

| Source                           | CSS class         | Color                        |
| -------------------------------- | ----------------- | ---------------------------- |
| Lua (deterministic decision)     | `.audit-tag.lua`  | Accent (sage)                |
| LLM (transcription / extraction) | `.audit-tag.llm`  | Violet `oklch(45% 0.16 290)` |
| Oban (job runner / scheduling)   | `.audit-tag.oban` | Amber `oklch(45% 0.14 65)`   |
| System (UI / notifications)      | `.audit-tag.sys`  | Muted neutral                |

Mono, 10px, uppercase, 0.04em. Use these for any event-stream surface.

### 4.7 Code blocks (Lua)

The Logic Inspector and Protocol Builder render Lua with a hand-written highlighter (`highlightLua` in `protocol.jsx`). Class tokens:

| Class        | Color         |
| ------------ | ------------- |
| `.c-comment` | sage italic   |
| `.c-string`  | rust          |
| `.c-kw`      | indigo bold   |
| `.c-num`     | rust          |
| `.c-type`    | accent (sage) |

Code is 12px Plex Mono, line-height 1.55, no syntax-highlighting libraries.

### 4.8 Status orb (patient call screen)

`.orb` is the central feedback object on the patient call. Three states:

| `data-phase` | Visual                                               |
| ------------ | ---------------------------------------------------- |
| `listening`  | Pulsing sage core, three concentric expanding halos. |
| `thinking`   | Scaled-down neutral core, rotating thin rings.       |
| `responding` | Sage core + voice-bar mask animating across the orb. |

Drive it by setting `data-phase` on the wrapper element. Never use bare colored circles for non-orb feedback elsewhere.

### 4.9 Audio waveform

The dual-lane waveform (`.audio-wave-big`) is the canonical clinical audio representation:

- **Top lane**: system voice, sage.
- **Bottom lane**: patient voice, neutral ink with amber bars for elevated-tone segments.
- **Pause/silence**: bars flatten to a 2px stub.
- **Markers** (`.amark`) pin to timestamps with three kinds: `pause` (muted), `tone` (amber), `keyword` (critical). Collision-aware stagger across 3 levels — re-use the algorithm in `nurse.jsx` (`markers = useMemo(...)`).

### 4.10 Prosody cards

Acoustic signals as longitudinal advisory chips. Severity variants:

| Class                    | Use                                     |
| ------------------------ | --------------------------------------- |
| `.prosody-card.sev-warn` | Amber — clinically meaningful deviation |
| `.prosody-card.sev-info` | Sage — noted but not actionable         |
| `.prosody-card.sev-ok`   | Green — within baseline                 |

Always pair the chip with a baseline reference and a 7-day sparkline. **Never** present a prosody signal as a sole alert trigger — the label must read as advisory.

### 4.11 Vital tile

`.vitals-grid > .vital[data-state]` — three-up grid, 1px hairlines between (gap:1px on a `--line` background). Each tile:

```
┌──────────────────────────┐
│ ♥ HEART RATE             │  ← icon + label (mono, muted)
│ 102 bpm     ▁▂▃▆▇        │  ← value (22px, color shifts on data-state) + sparkline
│ target 60–100 bpm        │  ← mono caption
└──────────────────────────┘
```

Color the value via `data-state` (`stable` / `warning` / `critical`), not via inline style. Sparkline colors follow the same state.

### 4.12 Logic trace row

The horizontal "step + value + weight" row used in Logic Inspector and Sim:

```
[✓]  calf_warmth == true              true       +0.35
```

Tick is 16px circle, accent-filled when fired. Use `.trace-row[data-fired="true"]` for the accent-tinted background. Weights are always `+0.NN` mono.

### 4.13 Tweaks panel

Use `<TweaksPanel>` + `useTweaks(DEFAULTS)` from `tweaks-panel.jsx`. The defaults block **must** be wrapped in `/*EDITMODE-BEGIN*/ … /*EDITMODE-END*/` markers so changes persist. See `app.jsx` for the live example.

Current tweaks: `density` (`comfortable` | `compact`), `alertTone` (`soft` | `traditional`).

---

## 5 · Screen recipes

### Recipe A — Hybrid list-detail (nurse triage pattern)

When showing **many entities** that triage to **one focused entity**, prefer queue + always-open detail:

1. `.nurse-header` — page title left, filter pills right (using `<Metric>` clickable cards).
2. `.nurse-body` grid: `380px 1fr`.
3. Left: search → sort row → scrollable patient rows (`.prow[data-status]`) → footer.
4. Right: stacked cards. **Lead with the alert banner** if `status === 'critical'`. Order: alert → vitals + meds → check-in (audio leads) → logic inspector → audit trail.

### Recipe B — Side-by-side authoring (protocol builder pattern)

Whenever a user authors something that compiles to a deterministic artefact:

```
┌──────────┬─────────────────────┬───────────────────────┐
│ Sidebar  │ Natural language    │ Generated artefact     │
│ (280px)  │ canvas (editable)   │ (read-only, monospace) │
├──────────┴─────────────────────┴───────────────────────┤
│ Simulation panel (inputs + result side-by-side)         │
└────────────────────────────────────────────────────────┘
```

- Edits to the NL pane debounce → show a transient `Compiling…` pill in the page subhead, then `Lua compiled · validated`.
- Compiled output is **never** directly editable from the same surface — provide an explicit "Edit raw" affordance.
- Always include a live simulator with synthetic inputs + score meter beneath.

### Recipe C — Voice surface (patient call pattern)

- Centered 88px orb above all else, halos sized for visual weight ≥ 60% of viewport height.
- One large prompt (`.ps-cue`, 19px, 600), one supporting line (`.ps-sub`, 13px, muted).
- Single primary action (red phone end-call). No more than 3 actions total. Tap targets ≥ 44px.
- Bottom: HIPAA / encryption footer in mono caption.

### Recipe D — Decision transparency

Any time the system has triggered an action on a patient's behalf, show the trace inline. Use the Logic Inspector pattern: protocol pill + `mono-tag` audit ID + Lua code + score trace + threshold meter. **Never** present an outcome without exposing the path.

---

## 6 · Patterns to avoid

- ❌ Gradient backgrounds (page, card, button). Brand gradient is for the mark only.
- ❌ Drop shadows on cards. Use 1px hairline borders.
- ❌ Decorative icons. Every icon must mean something clinical or navigational.
- ❌ Sentence-case `.pill` text. Pills are mono uppercase short codes.
- ❌ Emoji.
- ❌ Inventing new accent colors. Extend tokens or reach for the existing accent.
- ❌ Treating the LLM as the decider. Always frame as: LLM extracts → Lua decides.
- ❌ Showing transcript without audio when both exist. Audio is canonical.
- ❌ Animations on data values. Sparkline lines do not animate; numbers do not count up.
- ❌ Toast notifications. Use the `.alert-banner` pattern inside the relevant card instead.
- ❌ Modal dialogs. Use the queue + detail pattern; if you truly need a modal, **don't**.

---

## 7 · Adding a new screen — checklist

1. **Mount inside the app shell.** Add a tab in `app.jsx`'s `<TopBar>`, render your component conditionally on `tab === "your-tab"`. Add a `data-screen-label` on the wrapper.
2. **Reuse `<NurseDashboard>` / `<ProtocolBuilder>` patterns** before writing new layouts. Most needs map to recipe A, B, or C above.
3. **Tokens only.** Search-and-replace forbids inline colors. Only `oklch()` tokens, brand-gradient hex (for the mark), and the highlighter colors.
4. **Density check.** Toggle `data-density="compact"` on `<html>`; the screen must remain useful.
5. **Tone check.** Toggle `data-tone="soft"`; alerts must remain legible.
6. **Provenance.** Any event you show in your screen must carry an audit tag (Lua / LLM / Oban / System).
7. **Voice surfaces only** if the screen is patient-facing. Otherwise use the dense clinical pattern.
8. **Add a recipe entry** to this doc once your pattern is reused twice.

---

## 8 · Engineering notes

- React 18.3.1 + Babel standalone (in-browser, for prototyping only). Pinned with integrity hashes in `PostOpGuard.html`.
- No bundler, no module system. Components register on `window` via `Object.assign(window, { ... })` at the bottom of each JSX file. **Each JSX file must use uniquely-named style objects** if you introduce any — global `const styles = {...}` will collide.
- State management: plain `useState` / `useMemo` / `useEffect`. No external store.
- Tweaks persist by posting `{type: '__edit_mode_set_keys'}` to the parent host; defaults live inside `/*EDITMODE-BEGIN*/ … /*EDITMODE-END*/` so the host can rewrite the JSON on disk.
- IDs and gradient references inside SVGs use `React.useId()` so multiple instances coexist.

---

## 9 · File map

```
PostOpGuard.html               ← console (1440px target, dev preview)
PostOpGuard-print.html         ← print export (3-page PDF, 1280×920 per page)
PostOpGuard (standalone).html  ← single-file offline export

# JSX files are just references.
app.jsx                        ← top bar, tab routing, Tweaks panel wiring
shared.jsx                     ← Icon, StatusPill, Trend, Sparkline, BrandMark, BrandWordmark
nurse.jsx                      ← Triage queue, patient detail, audio hero, prosody, logic inspector, audit
protocol.jsx                   ← NL canvas, generated Lua, logic simulation
patient.jsx                    ← iOS-framed mid-call screen + status orb
data.js                        ← mock clinical data (patients, transcripts, protocols)

styles.css                     ← tokens, app shell, pills, buttons, cards, audit tags
nurse.css                      ← nurse surface
protocol.css                   ← protocol surface
patient.css                    ← patient surface

tweaks-panel.jsx               ← floating Tweaks shell + form controls
ios-frame.jsx                  ← iPhone bezel for patient surfaces

design-system/
  DESIGN_SYSTEM.md             ← this file
  design-system.html           ← visual reference (live tokens, components, swatches)
```

Read the visual reference at `./design-system.html` to see every token, pill, vital tile, and pattern rendered.
