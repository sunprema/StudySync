defmodule StudysyncWeb.LibraryComponents do
  @moduledoc """
  Phoenix components for the workspace library — Direction 01: Margin Notes.

  Naming and styling follow CLAUDE.md §5. New components should live here
  rather than in `core_components.ex` (which holds Phoenix-generated
  primitives like inputs and tables).
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :resource, :map, required: true
  attr :uploader_email, :string, default: nil

  def resource_card(assigns) do
    ~H"""
    <article
      id={"resource-#{@resource.id}"}
      class="border-b border-paper-2 py-5 flex items-baseline justify-between gap-6"
    >
      <div class="min-w-0">
        <h3 class="font-display text-2xl text-ink truncate">{@resource.title}</h3>
        <p class="font-mono text-xs uppercase tracking-widest text-ink-soft mt-2">
          <span class="num">{@resource.page_count}</span>
          pages · {format_date(@resource.inserted_at)}<span :if={@uploader_email}> · {@uploader_email}</span>
        </p>
      </div>
    </article>
    """
  end

  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %d, %Y")

  @doc """
  Inline footnote marker — small terracotta superscript with the annotation
  number. Lives inline next to the prose word that anchors the annotation,
  and matches the marker the canvas renders over the rect.
  """
  attr :number, :integer, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  def footnote_marker(assigns) do
    ~H"""
    <sup
      class={["font-mono text-[0.65em] text-terracotta align-super num", @class]}
      {@rest}
    >
      {@number}
    </sup>
    """
  end

  @doc """
  Margin note card — one annotation as it appears in the right margin. Number
  badge on the left, snippet (italic, ink-soft) above the user's body text,
  author + timestamp footer in mono caps.

  Clicking the card focuses it (Slice 5 bi-directional sync) and scrolls the
  PDF to the source. Hovering dispatches a DOM event the canvas listens for to
  dim non-matching markers.
  """
  attr :number, :integer, required: true
  attr :annotation, :map, required: true
  attr :author_email, :string, default: nil
  attr :active?, :boolean, default: false
  attr :reply_count, :integer, default: 0
  attr :expanded?, :boolean, default: false
  slot :thread

  def margin_note(assigns) do
    ~H"""
    <article
      id={"margin-note-#{@annotation.id}"}
      data-annotation-id={@annotation.id}
      class={[
        "pl-4 py-3 cursor-pointer transition-colors",
        "border-l-2",
        if(@active?,
          do: "border-terracotta bg-paper/60",
          else: "border-paper-2 hover:border-terracotta/50"
        )
      ]}
      phx-click={JS.push("select_annotation", value: %{id: @annotation.id})}
      phx-mouseover={
        JS.dispatch("studysync:annotation-hover",
          to: "body",
          detail: %{id: @annotation.id}
        )
      }
      phx-mouseout={JS.dispatch("studysync:annotation-hover", to: "body", detail: %{id: nil})}
    >
      <div class="flex items-baseline gap-2 mb-1">
        <.footnote_marker number={@number} class="!text-[0.85rem]" />
        <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft truncate">
          {@author_email || "unknown"}
        </p>
      </div>

      <blockquote class="font-serif italic text-ink-soft text-sm border-l border-paper-2/70 pl-2 mb-2 truncate">
        “{@annotation.text}”
      </blockquote>

      <p class="font-serif text-ink text-sm whitespace-pre-wrap">{@annotation.body}</p>

      <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft mt-2">
        {format_date(@annotation.inserted_at)}
      </p>

      <button
        type="button"
        phx-click={JS.push("toggle_thread", value: %{id: @annotation.id})}
        aria-expanded={to_string(@expanded?)}
        aria-controls={"thread-#{@annotation.id}"}
        class={[
          "mt-3 font-mono text-[10px] uppercase tracking-widest cursor-pointer",
          "hover:text-terracotta transition-colors",
          if(@expanded?, do: "text-terracotta", else: "text-ink-soft")
        ]}
      >
        <%= cond do %>
          <% @expanded? -> %>
            Hide thread
          <% @reply_count > 0 -> %>
            {@reply_count} {if @reply_count == 1, do: "reply", else: "replies"}
          <% true -> %>
            Reply
        <% end %>
      </button>

      <div :if={@expanded?} id={"thread-#{@annotation.id}"} class="mt-3">
        {render_slot(@thread)}
      </div>
    </article>
    """
  end

  @doc """
  Single reply within an annotation thread. Avatar (initials), body, mono
  caps timestamp footer. AI replies get a small "AI" tag in the same row as
  the author label — never lean on emoji.
  """
  attr :reply, :map, required: true
  attr :author_email, :string, default: nil

  def thread_reply(assigns) do
    ~H"""
    <article
      id={"thread-reply-#{@reply.id}"}
      class="flex gap-3 py-3 border-t border-paper-2/60 first:border-t-0"
    >
      <div
        aria-hidden="true"
        class={[
          "shrink-0 w-7 h-7 rounded-full flex items-center justify-center",
          "font-mono text-[10px] uppercase tracking-widest",
          if(@reply.is_ai_response,
            do: "bg-terracotta/15 text-terracotta",
            else: "bg-paper-2 text-ink-soft"
          )
        ]}
      >
        {initials(@author_email, @reply.is_ai_response)}
      </div>

      <div class="min-w-0 flex-1">
        <div class="flex items-baseline gap-2 mb-1">
          <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft truncate">
            {@author_email || "unknown"}
          </p>
          <span
            :if={@reply.is_ai_response}
            class="font-mono text-[9px] uppercase tracking-widest text-terracotta border border-terracotta/40 px-1 py-px rounded-sm"
          >
            AI
          </span>
        </div>

        <p class="font-serif text-ink text-sm whitespace-pre-wrap">{@reply.body}</p>

        <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft mt-2">
          {format_date(@reply.inserted_at)}
        </p>
      </div>
    </article>
    """
  end

  defp initials(_, true), do: "AI"
  defp initials(nil, _), do: "·"

  defp initials(email, _) do
    email
    |> String.split("@", parts: 2)
    |> List.first()
    |> String.slice(0, 2)
    |> String.upcase()
  end

  @doc """
  Static chapter rail — left vertical column with chapter labels, mono caps.

  Slice 3 ships the layout shell; chapters are illustrative until the
  resource gains a real outline (later slice).
  """
  attr :chapters, :list, default: []

  def chapter_rail(assigns) do
    assigns =
      if assigns.chapters == [] do
        Phoenix.Component.assign(assigns, :chapters, ["I", "II", "III", "IV", "V"])
      else
        assigns
      end

    ~H"""
    <nav
      aria-label="Chapters"
      class="hidden md:flex w-10 shrink-0 flex-col items-center pt-12 gap-8 border-r border-paper-2 text-ink-soft"
    >
      <span
        :for={label <- @chapters}
        class="font-mono text-[10px] uppercase tracking-widest [writing-mode:vertical-rl] rotate-180"
      >
        {label}
      </span>
    </nav>
    """
  end
end
