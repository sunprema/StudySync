defmodule StudysyncWeb.LibraryComponents do
  @moduledoc """
  Phoenix components for the workspace library — Direction 01: Margin Notes.

  Naming and styling follow CLAUDE.md §5. New components should live here
  rather than in `core_components.ex` (which holds Phoenix-generated
  primitives like inputs and tables).
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: StudysyncWeb.Endpoint,
    router: StudysyncWeb.Router,
    statics: StudysyncWeb.static_paths()

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
  attr :focal?, :boolean, default: false
  attr :reply_count, :integer, default: 0
  attr :expanded?, :boolean, default: false
  slot :thread

  def margin_note(assigns) do
    ~H"""
    <article
      id={"margin-note-#{@annotation.id}"}
      data-annotation-id={@annotation.id}
      data-annotation-type={@annotation.type}
      data-focal-page={if @focal?, do: "true", else: "false"}
      role="button"
      tabindex="0"
      aria-label={"Annotation #{@number} on page #{@annotation.page_number}"}
      aria-pressed={to_string(@active?)}
      class={[
        "px-4 py-3 cursor-pointer transition-colors rounded-sm",
        "border-l-2",
        "focus:outline-none focus-visible:ring-2 focus-visible:ring-terracotta/60 focus-visible:ring-offset-1 focus-visible:ring-offset-paper-2",
        cond do
          @active? -> "border-terracotta bg-paper"
          @focal? -> "bg-paper " <> type_border_class(@annotation.type)
          true -> type_border_class(@annotation.type)
        end
      ]}
      phx-click={JS.push("select_annotation", value: %{id: @annotation.id})}
      phx-keydown={JS.push("select_annotation", value: %{id: @annotation.id})}
      phx-key="Enter"
      phx-mouseover={
        JS.dispatch("studysync:annotation-hover",
          to: "body",
          detail: %{id: @annotation.id}
        )
      }
      phx-mouseout={JS.dispatch("studysync:annotation-hover", to: "body", detail: %{id: nil})}
      phx-focus={
        JS.dispatch("studysync:annotation-hover",
          to: "body",
          detail: %{id: @annotation.id}
        )
      }
      phx-blur={JS.dispatch("studysync:annotation-hover", to: "body", detail: %{id: nil})}
    >
      <div class="flex items-baseline gap-2 mb-1 flex-wrap">
        <.footnote_marker number={@number} class="!text-[0.85rem]" />
        <span
          :if={@annotation.type != :comment}
          class={[
            "font-mono text-[9px] uppercase tracking-widest px-1 py-px rounded-sm border",
            type_tag_classes(@annotation.type)
          ]}
        >
          {type_tag_label(@annotation.type)}
        </span>
        <span
          :if={@annotation.visibility == :private}
          aria-label="Private — only visible to you"
          title="Private — only visible to you"
          class="inline-flex items-center gap-1 font-mono text-[9px] uppercase tracking-widest text-ink-soft border border-paper-2 px-1 py-px rounded-sm"
        >
          <span class="hero-lock-closed-mini size-3" aria-hidden="true"></span> Private
        </span>
        <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft truncate">
          {@author_email || "unknown"}
        </p>
      </div>

      <blockquote class={[
        "font-serif italic text-ink-soft text-sm border-l pl-2 mb-2 truncate",
        type_quote_border_class(@annotation.type)
      ]}>
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

  # Per-type visual treatment (Slice 10). Comments stay quiet — they're the
  # most common type, and adding a tag to every card would muddy the rail.
  # Questions/puzzles get a small mono-caps label and a pastel tint on the
  # left border + snippet quote rule, mapping to the highlight tints in
  # CLAUDE.md §5.1.
  defp type_tag_label(:question), do: "Question"
  defp type_tag_label(:puzzle), do: "Puzzle"
  defp type_tag_label(:ai_response), do: "AI"
  defp type_tag_label(_), do: "Note"

  defp type_tag_classes(:question), do: "text-mint border-mint/60 bg-mint/15"
  defp type_tag_classes(:puzzle), do: "text-lavender border-lavender/60 bg-lavender/20"
  defp type_tag_classes(:ai_response), do: "text-terracotta border-terracotta/40"
  defp type_tag_classes(_), do: "text-ink-soft border-paper-2"

  defp type_border_class(:question), do: "border-mint/70 hover:border-mint"
  defp type_border_class(:puzzle), do: "border-lavender/70 hover:border-lavender"
  defp type_border_class(_), do: "border-paper-2 hover:border-terracotta/50"

  defp type_quote_border_class(:question), do: "border-mint/60"
  defp type_quote_border_class(:puzzle), do: "border-lavender/60"
  defp type_quote_border_class(_), do: "border-paper-2/70"

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
  Single row in the workspace's Recent activity rail (Slice 8).

  Avatar (initials), action verb in mono caps, italic snippet, then a mono
  caps footer with the page number and a relative timestamp. When the event
  carries a `resource_id`, the whole row is a `<.link navigate>` to the
  reader; an `annotation_id`, when present, is forwarded as a query param so
  the reader can focus and scroll to that annotation on mount.
  """
  attr :event, :map, required: true
  attr :workspace_id, :string, required: true
  attr :now, :any, default: nil

  def activity_item(assigns) do
    assigns =
      if assigns[:now],
        do: assigns,
        else: Phoenix.Component.assign(assigns, :now, DateTime.utc_now())

    ~H"""
    <.link
      :if={@event.resource_id}
      id={"activity-#{@event.id}"}
      navigate={activity_link(@workspace_id, @event)}
      class="flex gap-3 py-3 border-b border-paper-2/60 hover:bg-paper/40 transition-colors cursor-pointer"
    >
      <.activity_item_body event={@event} now={@now} />
    </.link>

    <article
      :if={!@event.resource_id}
      id={"activity-#{@event.id}"}
      class="flex gap-3 py-3 border-b border-paper-2/60"
    >
      <.activity_item_body event={@event} now={@now} />
    </article>
    """
  end

  attr :event, :map, required: true
  attr :now, :any, required: true

  defp activity_item_body(assigns) do
    ~H"""
    <div
      aria-hidden="true"
      class="shrink-0 w-7 h-7 rounded-full bg-paper-2 text-ink-soft flex items-center justify-center font-mono text-[10px] uppercase tracking-widest"
    >
      {activity_initials(@event.actor_email)}
    </div>

    <div class="min-w-0 flex-1">
      <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft truncate">
        <span>{@event.actor_email || "unknown"}</span>
        <span> · </span>
        <span class="text-terracotta">{action_label(@event.type)}</span>
      </p>

      <p :if={@event.snippet} class="font-serif italic text-ink text-sm mt-1 line-clamp-2">
        “{@event.snippet}”
      </p>

      <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft mt-2 truncate">
        <span :if={@event.resource_title}>{@event.resource_title}</span>
        <span :if={@event.page_number}>
          <span :if={@event.resource_title}> · </span>
          P. <span class="num">{@event.page_number}</span>
        </span>
        <span> · </span>
        <span>{relative_time(@event.inserted_at, @now)}</span>
      </p>
    </div>
    """
  end

  # Deep-link target: prefer focusing the source annotation; fall back to a
  # plain page anchor for stamp events (no annotation), and finally the bare
  # reader URL when even page is missing.
  defp activity_link(workspace_id, %{resource_id: resource_id, annotation_id: annotation_id})
       when not is_nil(annotation_id) do
    ~p"/workspaces/#{workspace_id}/library/#{resource_id}?annotation=#{annotation_id}"
  end

  defp activity_link(workspace_id, %{resource_id: resource_id, page_number: page})
       when not is_nil(page) do
    ~p"/workspaces/#{workspace_id}/library/#{resource_id}?page=#{page}"
  end

  defp activity_link(workspace_id, %{resource_id: resource_id}) do
    ~p"/workspaces/#{workspace_id}/library/#{resource_id}"
  end

  defp action_label(:highlighted), do: "highlighted"
  defp action_label(:commented), do: "commented"
  defp action_label(:completed_chapter), do: "finished a chapter"
  defp action_label(:stamped), do: "stamped"
  defp action_label(other), do: to_string(other)

  defp activity_initials(nil), do: "·"

  defp activity_initials(email) do
    email
    |> String.split("@", parts: 2)
    |> List.first()
    |> String.slice(0, 2)
    |> String.upcase()
  end

  defp relative_time(%DateTime{} = at, now) do
    diff = DateTime.diff(now, at, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(at, "%b %d")
    end
  end

  defp relative_time(_, _), do: ""

  @doc """
  Horizontal progress timeline with avatar pins (Slice 9).

  A flat paper-2 track spans the full width. Each member is rendered as an
  initials circle pinned to their `progress_percent` along the track. The
  current actor's pin is bumped in size and gets a terracotta ring so a
  reader can find themselves at a glance. Multiple members at the same
  progress fan apart vertically rather than overlapping.

  `members` is a list of maps:

      %{
        user_id: id,
        email: "...",          # used to compute initials + label
        progress_percent: 0..100
      }
  """
  attr :members, :list, required: true
  attr :current_user_id, :any, default: nil
  attr :class, :string, default: nil

  def progress_timeline(assigns) do
    ~H"""
    <div class={["w-full", @class]}>
      <div class="relative h-12 mt-2">
        <div class="absolute left-0 right-0 top-1/2 h-px bg-paper-2 -translate-y-1/2"></div>
        <div
          :for={{member, idx} <- Enum.with_index(@members)}
          class="absolute top-1/2 -translate-y-1/2"
          style={"left: #{member.progress_percent}%; transform: translate(-50%, calc(-50% + #{pin_offset(idx)}px));"}
          title={"#{member.email} · #{member.progress_percent}%"}
        >
          <div class={[
            "rounded-full flex items-center justify-center",
            "font-mono uppercase tracking-widest",
            if(@current_user_id && member.user_id == @current_user_id,
              do: "w-8 h-8 text-[10px] bg-terracotta text-paper ring-2 ring-terracotta/30",
              else: "w-7 h-7 text-[9px] bg-paper-2 text-ink-soft border border-paper-2"
            )
          ]}>
            {member_initials(member.email)}
          </div>
        </div>

        <span class="absolute left-0 -bottom-5 font-mono text-[10px] uppercase tracking-widest text-ink-soft">
          P. <span class="num">1</span>
        </span>
        <span class="absolute right-0 -bottom-5 font-mono text-[10px] uppercase tracking-widest text-ink-soft">
          End
        </span>
      </div>
    </div>
    """
  end

  defp pin_offset(idx) when rem(idx, 2) == 0, do: -8
  defp pin_offset(_), do: 8

  defp member_initials(nil), do: "·"

  defp member_initials(email) do
    email
    |> String.split("@", parts: 2)
    |> List.first()
    |> String.slice(0, 2)
    |> String.upcase()
  end

  @doc """
  Single reader card on the workspace dashboard (Slice 9).

  Avatar + email, a one-word status, percentage in tabular nums, time-spent
  in mono caps, and a hairline progress bar. Self gets a terracotta accent
  border on the left.
  """
  attr :member, :map, required: true
  attr :is_self, :boolean, default: false
  attr :class, :string, default: nil

  def reader_card(assigns) do
    ~H"""
    <article class={[
      "p-4 border bg-paper",
      if(@is_self, do: "border-terracotta/60", else: "border-paper-2"),
      "border-l-2",
      if(@is_self, do: "border-l-terracotta", else: "border-l-paper-2"),
      @class
    ]}>
      <div class="flex items-center gap-3">
        <div
          aria-hidden="true"
          class={[
            "shrink-0 w-9 h-9 rounded-full flex items-center justify-center",
            "font-mono text-[11px] uppercase tracking-widest",
            if(@is_self, do: "bg-terracotta text-paper", else: "bg-paper-2 text-ink-soft")
          ]}
        >
          {member_initials(@member.email)}
        </div>

        <div class="min-w-0 flex-1">
          <p class="font-serif text-ink truncate">{@member.email || "unknown"}</p>
          <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft">
            {reader_status(@member.progress_percent)}
          </p>
        </div>

        <p class="font-display text-2xl text-ink num shrink-0">
          {@member.progress_percent}<span class="text-base text-ink-soft">%</span>
        </p>
      </div>

      <div class="mt-3 h-px bg-paper-2 w-full">
        <div
          class="h-px bg-terracotta"
          style={"width: #{@member.progress_percent}%;"}
        >
        </div>
      </div>

      <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft mt-3">
        {format_duration(Map.get(@member, :time_spent_seconds, 0))} on the page
      </p>
    </article>
    """
  end

  defp reader_status(0), do: "Not started"
  defp reader_status(p) when p >= 100, do: "Finished"
  defp reader_status(p) when p >= 75, do: "Almost done"
  defp reader_status(p) when p >= 25, do: "Reading"
  defp reader_status(_), do: "Just started"

  defp format_duration(nil), do: "—"
  defp format_duration(seconds) when is_integer(seconds) and seconds < 60, do: "<1m"

  defp format_duration(seconds) when is_integer(seconds) do
    cond do
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{div(seconds, 3600)}h #{rem(div(seconds, 60), 60)}m"
      true -> "#{div(seconds, 86_400)}d #{rem(div(seconds, 3600), 24)}h"
    end
  end

  defp format_duration(_), do: "—"

  @doc """
  Milestone panel (Slice 12) — lists admin-placed checkpoints for the current
  resource in the margin column.

  Each row shows the milestone label in serif, page number + creator email in
  mono caps. The panel sits above the annotation list so a reader can see the
  flagposts before diving into the comment thread.

  `milestones` is a list of `Studysync.Progress.MilestoneMarker` structs (with
  `:created_by` loaded).
  """
  attr :milestones, :list, required: true
  attr :total_readers, :integer, default: 0
  attr :class, :string, default: nil

  def milestone_panel(assigns) do
    ~H"""
    <section class={["border border-paper-2 bg-paper px-4 py-3", @class]}>
      <header class="flex items-baseline justify-between mb-2">
        <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft">
          Milestones · <span class="num">{length(@milestones)}</span>
        </p>
      </header>

      <ol class="space-y-2">
        <li
          :for={milestone <- @milestones}
          id={"milestone-#{milestone.id}"}
          class="border-l-2 border-terracotta/60 pl-3"
        >
          <p class="font-serif text-ink text-sm">{milestone.label}</p>
          <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft mt-1">
            P. <span class="num">{milestone.page_number}</span>
            <span :if={milestone_creator_email(milestone)}>
              · {milestone_creator_email(milestone)}
            </span>
            <span class="text-terracotta">
              · <span class="num">{stamp_count(milestone)}</span>
              / <span class="num">{@total_readers}</span>
              stamped
            </span>
          </p>
        </li>
      </ol>
    </section>
    """
  end

  defp stamp_count(%{stamp_count: n}) when is_integer(n), do: n
  defp stamp_count(_), do: 0

  defp milestone_creator_email(%{created_by: %{email: email}}) when not is_nil(email),
    do: to_string(email)

  defp milestone_creator_email(_), do: nil

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
