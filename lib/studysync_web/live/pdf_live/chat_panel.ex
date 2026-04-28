defmodule StudysyncWeb.PdfLive.ChatPanel do
  @moduledoc """
  Bottom-right chat drawer for the reader (Slice 18).

  Collapsed: a small `CHAT · N` pill in the bottom-right corner of the page
  surface, where N is the unread count since the panel was last expanded.
  Expanded: a ~360 × ~50vh panel with a scrolling message list, a "here
  now" line, and a reply form.

  ## State ownership

  This component owns the panel's local UI state (open/closed, unread
  count, the form changeset, the message stream). Subscription to chat
  PubSub lives in the parent LiveView (`StudysyncWeb.PdfLive.Show`)
  because LiveComponents don't own a process. The parent forwards new
  messages via `send_update/2` and we land them in the stream here.

  ## Optimistic UI

  `Studysync.Chat.PubSub.broadcast_message_sent/1` uses
  `Phoenix.PubSub.broadcast_from!`, so the sender never receives its own
  broadcast. That means we have to insert the sender's message into the
  local stream ourselves on success — no double-render risk, and the
  optimistic insert lands instantly.
  """

  use StudysyncWeb, :live_component

  alias Studysync.Chat
  alias Studysync.Chat.Message

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> stream_configure(:messages, dom_id: &("chat-message-" <> &1.id))
     |> stream(:messages, [])
     |> assign(:open?, false)
     |> assign(:unread, 0)
     |> assign(:error, nil)
     |> assign(:body_value, "")
     |> assign(:seeded?, false)
     |> assign(:here_now, 0)}
  end

  @impl true
  def update(%{new_message: %Message{} = message}, socket) do
    socket =
      socket
      |> stream_insert(:messages, message)
      |> bump_unread_if_closed()
      |> push_event("chat:message-inserted", %{from_self?: false})

    {:ok, socket}
  end

  # Initial mount and presence-diff updates both flow through here. The
  # parent always passes `:id` (required by send_update); other keys are
  # merged in if present. `seeded?` guards the one-time stream seed so a
  # later presence-only update doesn't double-insert the initial messages.
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> seed_initial_messages(assigns)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle", _params, socket) do
    new_open? = !socket.assigns.open?

    socket =
      socket
      |> assign(:open?, new_open?)
      |> assign(:unread, 0)

    # On expand, ask the scroll hook to land at the latest message — the
    # hook's mounted() callback ran while the panel was hidden, so it
    # never saw a useful scrollHeight. Only push on the closed→open edge.
    socket =
      if new_open? do
        push_event(socket, "chat:show", %{})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
    case Chat.send_message(socket.assigns.current_user, socket.assigns.resource_id, body) do
      {:ok, %Message{} = message} ->
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:error, nil)
         |> assign(:body_value, "")
         |> push_event("chat:message-inserted", %{from_self?: true})}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, error_message(reason)) |> assign(:body_value, body)}
    end
  end

  # ---------- helpers ----------

  defp seed_initial_messages(socket, %{initial_messages: messages}) when is_list(messages) do
    if socket.assigns.seeded? do
      socket
    else
      Enum.reduce(messages, socket, &stream_insert(&2, :messages, &1))
      |> assign(:seeded?, true)
    end
  end

  defp seed_initial_messages(socket, _), do: socket

  defp bump_unread_if_closed(socket) do
    if socket.assigns.open? do
      socket
    else
      assign(socket, :unread, socket.assigns.unread + 1)
    end
  end

  defp error_message(:empty_body), do: "Message can't be blank."
  defp error_message(:body_too_long), do: "Keep it under #{Chat.max_body_length()} characters."
  defp error_message(:rate_limited), do: "Slow down — wait a moment before sending again."
  defp error_message(:unauthorized), do: "You're not a member of this workspace."
  defp error_message(_), do: "Couldn't send. Try again."

  # ---------- render ----------

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="absolute bottom-6 right-6 z-30 flex flex-col items-end pointer-events-none"
    >
      <%!--
        Both the panel and the pill stay in the DOM at all times — the
        collapsed state hides the panel via the `hidden` class. Streams
        require their container to be continuously rendered for inserts
        to land; toggling visibility with CSS keeps the stream's DOM
        anchor stable across opens/closes.
      --%>
      <section
        class={[
          "pointer-events-auto w-[360px] max-h-[50vh] flex-col bg-paper-2 border border-paper-2/80 rounded-sm",
          if(@open?, do: "flex", else: "hidden")
        ]}
        aria-label="Study-room chat"
        aria-hidden={to_string(!@open?)}
      >
        <header class="flex items-center justify-between px-4 py-3 border-b border-paper/60">
          <div>
            <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft">
              Chat · <span class="num">{@here_now}</span> here now
            </p>
            <p class="font-mono text-[9px] uppercase tracking-widest text-ink-soft/70 mt-0.5">
              Transient — clears on restart
            </p>
          </div>
          <button
            type="button"
            phx-click="toggle"
            phx-target={@myself}
            aria-label="Close chat"
            class="font-mono text-[11px] uppercase tracking-widest text-ink-soft hover:text-terracotta cursor-pointer"
          >
            Close
          </button>
        </header>

        <div
          id={"#{@id}-scroll"}
          phx-hook="ChatScroll"
          phx-update="stream"
          class="flex-1 overflow-y-auto px-4 py-3 space-y-3"
        >
          <div
            :for={{dom_id, message} <- @streams.messages}
            id={dom_id}
            class="flex flex-col gap-1"
          >
            <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft">
              <span class="text-terracotta">{display_name(message)}</span>
              <span> · </span>
              <span class="num">{format_time(message.sent_at)}</span>
            </p>
            <p class="text-sm text-ink leading-relaxed whitespace-pre-wrap break-words">
              {message.body}
            </p>
          </div>
        </div>

        <footer class="border-t border-paper/60 px-4 py-3 space-y-2">
          <p
            :if={@error}
            class="font-mono text-[10px] uppercase tracking-widest text-terracotta"
          >
            {@error}
          </p>
          <form
            phx-submit="send_message"
            phx-target={@myself}
            class="flex items-end gap-2"
          >
            <label for={"#{@id}-body"} class="sr-only">Message</label>
            <textarea
              id={"#{@id}-body"}
              name="message[body]"
              rows="2"
              maxlength={Chat.max_body_length()}
              placeholder="Say something to the room…"
              class="flex-1 resize-none bg-paper border border-paper-2 rounded-sm px-3 py-2 text-sm text-ink placeholder:text-ink-soft/60 focus:outline-none focus:border-terracotta"
            >{@body_value}</textarea>
            <button
              type="submit"
              class="font-mono text-[10px] uppercase tracking-widest px-3 py-2 rounded-sm border border-terracotta bg-terracotta text-paper hover:bg-terracotta/90 transition-colors cursor-pointer"
            >
              Send
            </button>
          </form>
        </footer>
      </section>

      <button
        type="button"
        phx-click="toggle"
        phx-target={@myself}
        class={[
          "pointer-events-auto font-mono text-[10px] uppercase tracking-widest px-3 py-2 rounded-sm border border-paper-2 bg-paper-2 text-ink hover:border-terracotta hover:text-terracotta transition-colors cursor-pointer items-center gap-2",
          if(@open?, do: "hidden", else: "flex")
        ]}
        aria-label={"Open chat. #{@unread} unread."}
        aria-hidden={to_string(@open?)}
      >
        <span>Chat</span>
        <span :if={@unread > 0} class="num text-terracotta">· {@unread}</span>
      </button>
    </div>
    """
  end

  defp display_name(%Message{user_email: email}) when is_binary(email) do
    email |> String.split("@") |> List.first() |> String.upcase()
  end

  defp format_time(%DateTime{} = dt) do
    dt
    |> DateTime.to_time()
    |> Time.truncate(:second)
    |> Time.to_string()
    |> String.slice(0, 5)
  end
end
