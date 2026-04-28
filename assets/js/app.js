import "vite/modulepreload-polyfill";
// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/studysync"
import topbar from "topbar"
import {getHooks} from "live_svelte"
import Components from "virtual:live-svelte-components"

// MarginColumn — listens for `scroll_to_margin_note` events from the LiveView
// (pushed when a marker is clicked in the PDF canvas) and smooth-scrolls the
// matching margin note into view. Pairs with PdfCanvasRenderer's reverse
// effect (active_annotation_id → page scroll) to give the bi-directional sync
// a low-latency feel without round-tripping for hover.
//
// Slice 16:
//   - 16.2: brief pulse animation on the destination card, mirroring the
//     marker-pulse in the canvas so navigation lands with a visible cue in
//     both directions.
//   - 16.3: listen on `studysync:annotation-hover` to dim non-matching margin
//     notes when a marker is hovered. Margin → canvas already works the
//     other way (each card dispatches the same event); this completes the
//     reverse direction without a server round-trip.
const MarginColumn = {
  mounted() {
    this._pulseTimer = null

    this.handleEvent("scroll_to_margin_note", ({id}) => {
      const el = this.el.querySelector(`#margin-note-${id}`)
      if (!el) return
      el.scrollIntoView({behavior: "smooth", block: "center"})
      this._pulse(el)
    })

    this._onHover = (e) => {
      const id = e.detail?.id ?? null
      this.el.querySelectorAll("[data-annotation-id]").forEach((card) => {
        if (id == null) {
          card.classList.remove("is-dim")
        } else if (card.dataset.annotationId === id) {
          card.classList.remove("is-dim")
        } else {
          card.classList.add("is-dim")
        }
      })
    }
    document.addEventListener("studysync:annotation-hover", this._onHover)
  },

  destroyed() {
    if (this._pulseTimer) clearTimeout(this._pulseTimer)
    if (this._onHover) document.removeEventListener("studysync:annotation-hover", this._onHover)
  },

  _pulse(el) {
    el.classList.remove("is-pulse")
    // Force a reflow so re-adding the class restarts the animation when the
    // user clicks the same marker twice in quick succession.
    void el.offsetWidth
    el.classList.add("is-pulse")
    if (this._pulseTimer) clearTimeout(this._pulseTimer)
    this._pulseTimer = setTimeout(() => el.classList.remove("is-pulse"), 1200)
  },
}

// ChatScroll — keeps the transient chat panel (Slice 18) pinned to the
// latest message. Three signals drive the scroll:
//
//   1. `beforeUpdate`/`updated` lifecycle. Snapshot whether the user was
//      near the bottom *before* the DOM patch, then re-pin to bottom in
//      `updated` if they were. Catches every stream insert (own + peer)
//      without depending on a server-pushed event arriving first.
//   2. `chat:message-inserted` with `from_self?: true`. The user just
//      sent the message, so scroll regardless of where they were
//      reading. Overrides the near-bottom check.
//   3. `chat:show`. Fired when the panel transitions from collapsed to
//      open. The hook's `mounted` ran while the section was hidden
//      (zero-sized), so there's no useful scroll state until expand.
const ChatScroll = {
  mounted() {
    this._wasNearBottom = true
    this._scrollToBottom()

    this.handleEvent("chat:message-inserted", (payload) => {
      const fromSelf = payload?.from_self ?? payload?.["from_self?"] ?? false
      if (fromSelf) {
        // Defer so the streamed-in node is in the DOM before we read
        // scrollHeight.
        requestAnimationFrame(() => this._scrollToBottom())
      }
    })

    this.handleEvent("chat:show", () => {
      requestAnimationFrame(() => this._scrollToBottom())
    })
  },

  beforeUpdate() {
    this._wasNearBottom = this._nearBottom()
  },

  updated() {
    if (this._wasNearBottom) {
      this._scrollToBottom()
    }
  },

  _nearBottom() {
    // When the panel is hidden the element is zero-sized; treat that as
    // "near bottom" so the next visible patch follows new content.
    if (this.el.clientHeight === 0) return true
    const slack = 80
    return this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight <= slack
  },

  _scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  },
}

// Theme — applies the current user's theme key (read from data-theme-key on
// mount) to <html data-theme="..."> immediately so the click-to-flip feels
// instant. The LiveView still persists the preference via the `set_theme`
// event; on subsequent mounts the root layout already renders the right
// data-theme, so this hook is mostly a no-op except after a click.
const Theme = {
  mounted() {
    this._apply()
  },

  updated() {
    this._apply()
  },

  _apply() {
    const key = this.el.dataset.themeKey
    if (!key) return
    if (document.documentElement.getAttribute("data-theme") !== key) {
      document.documentElement.setAttribute("data-theme", key)
    }
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...getHooks(Components), MarginColumn, Theme, ChatScroll},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
