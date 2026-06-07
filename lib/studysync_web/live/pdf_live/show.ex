defmodule StudysyncWeb.PdfLive.Show do
  use StudysyncWeb, :live_view

  alias Studysync.AI.AnswerWorker
  alias Studysync.Annotations
  alias Studysync.Annotations.PubSub, as: AnnotationsPubSub
  alias Studysync.Chat
  alias Studysync.Chat.PubSub, as: ChatPubSub
  alias Studysync.Library
  alias Studysync.Presence
  alias Studysync.Progress
  alias Studysync.Progress.CollectiveInsight
  alias Studysync.Sprints
  alias Studysync.Workspaces

  @chat_panel_id "chat-panel"

  require Ash.Query

  def mount(%{"workspace_id" => workspace_id, "id" => id} = params, _session, socket) do
    actor = socket.assigns.current_user

    case Library.get_resource(id, actor: actor, load: [:uploaded_by]) do
      {:ok, resource}
      when not is_nil(resource) and resource.workspace_id == workspace_id ->
        # Slice 15a (revert): a single eager whole-book load. The reader
        # always sees every peer annotation in the margin column, with
        # the focal page highlighted by background color. Cheaper than it
        # sounds — see PERFORMANCE.md (200 annotations ≈ 16ms p50 with
        # `:user` and `:reply_count` preloaded).
        annotations = Annotations.list_annotations_for_resource(resource.id, actor: actor)

        milestones = load_milestones(resource.id, actor)
        collective_insights = load_collective_insights(resource.id)
        active_sprint = Sprints.active_sprint(resource.id)
        sprint_member? = active_sprint && Sprints.sprint_member?(active_sprint, actor.id)
        is_admin? = Workspaces.actor_admin?(workspace_id, actor)
        total_readers = count_workspace_members(workspace_id)

        if connected?(socket) do
          AnnotationsPubSub.subscribe(resource.id)
          ChatPubSub.subscribe(resource.id)
          if active_sprint, do: schedule_sprint_tick()

          # Slice 18.8 — track presence on the chat topic so the panel can
          # show "X here now". Presence auto-untracks when this process exits.
          {:ok, _} =
            Presence.track(
              self(),
              ChatPubSub.topic(resource.id),
              actor.id,
              %{email: to_string(actor.email)}
            )
        end

        initial_chat_messages = Chat.recent(resource.id)
        chat_here_now = chat_here_now(resource.id)
        readers_here = readers_here_list(resource.id, actor)

        # Activity-feed deep links: `?annotation=<id>` focuses the annotation
        # (and snaps focal_page to its page); `?page=<n>` is a softer fallback
        # for events without an annotation (e.g. stamps). The Svelte canvas
        # reacts to `active_annotation_id` to scroll the source page into view.
        {initial_active_id, initial_focal_page} =
          deep_link_target(params, annotations, resource.page_count)

        socket =
          socket
          |> assign(:resource, resource)
          |> assign(:workspace_id, workspace_id)
          |> assign(:file_url, ~p"/resources/#{resource.id}/file")
          |> assign(:page_title, resource.title)
          |> assign(:annotations, annotations)
          |> assign(:focal_page, initial_focal_page)
          |> assign(:selection, nil)
          |> assign(:annotation_form, nil)
          |> assign(:annotation_form_type, nil)
          |> assign(:active_annotation_id, initial_active_id)
          |> assign(:expanded_thread_id, nil)
          |> assign(:thread_replies, [])
          |> assign(:reply_form, nil)
          |> assign(:filter_type, :all)
          |> assign(:filter_scope, :all)
          |> assign(:milestones, milestones)
          |> assign(:collective_insights, collective_insights)
          |> assign(:active_sprint, active_sprint)
          |> assign(:sprint_member?, sprint_member?)
          |> assign(:sprint_countdown, sprint_countdown(active_sprint))
          |> assign(:show_sprint_form, false)
          |> assign(:compare_notes, nil)
          |> assign(:is_admin?, is_admin?)
          |> assign(:total_readers, total_readers)
          |> assign(:milestone_form, nil)
          |> assign(:milestone_pending_placement, nil)
          |> assign(:chapters, [])
          |> assign(:page_readers, %{})
          |> assign(:ai_pending_annotation_ids, MapSet.new())
          |> assign(:initial_chat_messages, initial_chat_messages)
          |> assign(:chat_here_now, chat_here_now)
          |> assign(:readers_here, readers_here)

        socket =
          if initial_active_id do
            push_event(socket, "scroll_to_margin_note", %{id: initial_active_id})
          else
            socket
          end

        {:ok, socket}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Resource not found.")
         |> push_navigate(to: ~p"/workspaces/#{workspace_id}/library")}
    end
  end

  # Resolve `?annotation=<id>` against the loaded list (drops silently if the
  # actor can't see it) or `?page=<n>` (clamped to the book's page count).
  # Returns `{active_annotation_id, focal_page}`.
  defp deep_link_target(params, annotations, page_count) do
    case Map.get(params, "annotation") do
      id when is_binary(id) and id != "" ->
        case Enum.find(annotations, &(&1.id == id)) do
          %{page_number: page} -> {id, page}
          _ -> {nil, fallback_focal_page(params, page_count)}
        end

      _ ->
        {nil, fallback_focal_page(params, page_count)}
    end
  end

  defp fallback_focal_page(params, page_count) do
    case Map.get(params, "page") do
      p when is_binary(p) and p != "" ->
        case Integer.parse(p) do
          {n, _} -> n |> max(1) |> min(max(page_count, 1))
          :error -> 1
        end

      _ ->
        1
    end
  end

  def terminate(_reason, socket) do
    if resource = Map.get(socket.assigns, :resource) do
      AnnotationsPubSub.unsubscribe(resource.id)
      ChatPubSub.unsubscribe(resource.id)

      # Broadcast departure so other readers' page-presence clears immediately.
      if actor = Map.get(socket.assigns, :current_user) do
        Phoenix.PubSub.broadcast_from!(
          Studysync.PubSub,
          self(),
          AnnotationsPubSub.topic(resource.id),
          {:reader_left, actor.id}
        )
      end
    end

    :ok
  end

  defp chat_here_now(resource_id) do
    resource_id |> ChatPubSub.topic() |> Presence.list() |> map_size()
  end

  # Returns a list of peer email strings currently tracking presence on the
  # resource's chat topic, excluding the current actor so they don't see
  # themselves in the "here now" cluster.
  defp readers_here_list(resource_id, actor) do
    actor_id = if is_map(actor), do: Map.get(actor, :id), else: nil

    resource_id
    |> ChatPubSub.topic()
    |> Presence.list()
    |> Enum.flat_map(fn {user_id, %{metas: metas}} ->
      if user_id == actor_id do
        []
      else
        metas
        |> List.first(%{})
        |> Map.get(:email)
        |> case do
          nil -> []
          "" -> []
          email -> [to_string(email)]
        end
      end
    end)
  end

  def render(assigns) do
    # Derive the scoped annotation list once. The template displays counts
    # in a few places (header line, filter chip badges) and short assign
    # names keep the HEEx interpolations on one line so the formatter
    # doesn't reflow them across `<span>` boundaries.
    scoped = scoped_annotations(assigns.annotations, assigns.filter_scope, assigns.focal_page)

    scoped_insights =
      case assigns.filter_scope do
        :page ->
          Enum.filter(assigns.collective_insights, &(&1.page_number == assigns.focal_page))

        _ ->
          assigns.collective_insights
      end

    assigns =
      assigns
      |> assign(:scoped_visible, visible_annotations(scoped, assigns.filter_type))
      |> assign(:scoped_total, length(scoped))
      |> assign(:scoped_filtered, filtered_count(scoped, assigns.filter_type))
      |> assign(:scoped_annotations, scoped)
      |> assign(:scoped_insights, scoped_insights)
      |> assign(:page_focal_count, page_scope_count(assigns.annotations, assigns.focal_page))
      |> assign(:chat_panel_id, @chat_panel_id)

    ~H"""
    <div
      class="flex h-screen w-full bg-paper text-ink overflow-hidden"
      phx-window-keydown="reader_keydown"
      phx-key="Escape"
    >
      <.chapter_rail chapters={@chapters} />

      <main class="flex-1 min-w-0 flex flex-col relative">
        <header class="topbar">
          <div class="flex-1 min-w-0">
            <p class="section-label">
              <.link
                navigate={~p"/workspaces/#{@workspace_id}/library"}
                class="hover:text-terracotta transition-colors"
              >
                Library
              </.link>
              <span class="text-ink-soft/40 mx-1">·</span>
              Reader
            </p>
            <h1 class="font-display text-2xl text-ink truncate leading-tight">{@resource.title}</h1>
          </div>

          <div class="flex items-center gap-4 shrink-0">
            <.reader_presence readers={@readers_here} />
            <span class="mono-tag num"><span class="num">{@resource.page_count}</span> pages</span>
            <.link
              navigate={~p"/workspaces/#{@workspace_id}/library/#{@resource.id}/board"}
              class="mono-tag hover:text-terracotta transition-colors"
            >
              Board ↗
            </.link>
            <button
              :if={!@active_sprint && !@show_sprint_form}
              phx-click="show_sprint_form"
              class="btn btn-ghost btn-xs section-label text-ink-soft hover:text-terracotta"
            >
              Start sprint
            </button>
            <StudysyncWeb.Layouts.user_menu current_user={@current_user} />
          </div>
        </header>

        <.sprint_form_banner :if={@show_sprint_form} resource={@resource} />

        <.sprint_banner
          :if={@active_sprint && !@show_sprint_form}
          sprint={@active_sprint}
          sprint_member?={@sprint_member?}
          countdown={@sprint_countdown}
        />

        <.compare_notes_modal :if={@compare_notes} notes={@compare_notes} sprint={@active_sprint} />

        <div id="pdf-canvas" class="flex-1 overflow-hidden">
          <.svelte
            name="PdfCanvasRenderer"
            props={
              %{
                file_url: @file_url,
                total_pages: @resource.page_count,
                annotations: svelte_annotations(@annotations),
                milestone_markers: svelte_milestones(@milestones),
                is_admin: @is_admin?,
                rubber_stamps: svelte_stamps(@milestones),
                current_user_id: @current_user.id,
                total_readers: @total_readers,
                active_annotation_id: @active_annotation_id,
                page_readers: svelte_page_readers(@page_readers),
                export_url: ~p"/resources/#{@resource.id}/journal.pdf"
              }
            }
            socket={@socket}
          />
        </div>

        <.live_component
          module={StudysyncWeb.PdfLive.ChatPanel}
          id={@chat_panel_id}
          resource_id={@resource.id}
          current_user={@current_user}
          initial_messages={@initial_chat_messages}
          here_now={@chat_here_now}
        />
      </main>

      <aside class="w-[360px] shrink-0 bg-paper-2 border-l border-paper-2 flex flex-col">
        <header class="px-5 py-4 border-b border-paper-2 space-y-3">
          <nav aria-label="Scope" class="flex gap-1.5">
            <.scope_tab
              scope={:all}
              label="All"
              count={length(@annotations)}
              active?={@filter_scope == :all}
            />
            <.scope_tab
              scope={:page}
              label="Page"
              count={@focal_page}
              active?={@filter_scope == :page}
            />
          </nav>

          <div class="flex items-baseline justify-between">
            <p class="section-label">
              Margin · <span class="num">{@scoped_filtered}</span>
              of <span class="num">{@scoped_total}</span>
              notes
            </p>
            <a
              href={~p"/resources/#{@resource.id}/journal.pdf"}
              target="_blank"
              rel="noopener"
              class="section-label text-terracotta hover:underline"
              title="Export your annotations as a reading journal PDF"
            >
              Export journal
            </a>
          </div>

          <nav aria-label="Filter by type" class="flex flex-wrap gap-1.5">
            <.filter_chip
              :for={chip <- filter_chips()}
              type={chip.type}
              label={chip.label}
              count={chip_count(@scoped_annotations, chip.type)}
              active?={@filter_type == chip.type}
            />
          </nav>
        </header>

        <div
          class="flex-1 overflow-y-auto px-6 py-6 space-y-2"
          id="margin-column"
          phx-hook="MarginColumn"
        >
          <.milestone_panel
            :if={@milestones != [] and !@milestone_form}
            milestones={@milestones}
            total_readers={@total_readers}
            current_user_id={@current_user.id}
            class="mb-4"
          />

          <.milestone_form_section
            :if={@milestone_form}
            form={@milestone_form}
            placement={@milestone_pending_placement}
          />

          <.annotation_form_section
            :if={@annotation_form}
            form={@annotation_form}
            selection={@selection}
            type={@annotation_form_type}
          />

          <.empty_state
            :if={@annotations == [] and !@annotation_form}
            kind={:no_annotations}
          />

          <.empty_state
            :if={@annotations != [] and @filter_scope == :page and @page_focal_count == 0}
            kind={:no_page_notes}
            label={focal_page_label(@focal_page)}
          />

          <.empty_state
            :if={
              @annotations != [] and
                (@filter_scope == :all or @page_focal_count > 0) and
                @scoped_filtered == 0
            }
            kind={:no_filtered}
            label={filter_label(@filter_type)}
          />

          <%!-- Slice 20 — GROUP LENS cards: one per page when 3+ readers annotated it. --%>
          <.group_lens_card :for={insight <- @scoped_insights} insight={insight} />

          <%!--
            Slice 15a (revert): single, stable list of every annotation in
            the book, sorted by (page, inserted_at). Cards on the focal
            page get a `bg-paper` background so they pop out of the
            paper-2 column without the layout shifting as the reader
            scrolls. Filter chips narrow this list in place. The scope
            tabs further narrow to only the focal page when active.
          --%>
          <div id="margin-notes" class="space-y-2">
            <.margin_note
              :for={annotation <- @scoped_visible}
              number={annotation.display_number}
              annotation={annotation}
              author_email={author_email(annotation)}
              active?={@active_annotation_id == annotation.id}
              focal?={annotation.page_number == @focal_page}
              reply_count={annotation.reply_count}
              expanded?={@expanded_thread_id == annotation.id}
              ai_pending?={MapSet.member?(@ai_pending_annotation_ids, annotation.id)}
            >
              <:thread>
                <.thread_reply
                  :for={reply <- @thread_replies || []}
                  reply={reply}
                  author_email={author_email(reply)}
                />

                <.reply_form
                  :if={@reply_form}
                  form={@reply_form}
                  annotation_id={annotation.id}
                />
              </:thread>
            </.margin_note>
          </div>
        </div>
      </aside>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :annotation_id, :string, required: true

  defp reply_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id={"reply-form-#{@annotation_id}"}
      phx-submit="submit_reply"
      class="mt-3 space-y-2"
    >
      <textarea
        id={@form[:body].id}
        name={@form[:body].name}
        rows="2"
        required
        autofocus
        placeholder="Reply…"
        class="w-full textarea text-sm font-serif"
      >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>

      <div class="flex gap-2">
        <button type="submit" class="btn btn-primary btn-sm">Reply</button>
      </div>
    </.form>
    """
  end

  attr :form, :any, required: true
  attr :placement, :map, required: true

  defp milestone_form_section(assigns) do
    ~H"""
    <section class="border-l-2 border-terracotta pl-4 py-3 mb-4 bg-paper">
      <p class="section-label text-terracotta mb-2">
        New milestone · page <span class="num">{@placement.page}</span>
      </p>

      <p class="font-serif italic text-ink-soft text-sm mb-3">
        A checkpoint your readers can stamp once they've reached it.
      </p>

      <.form for={@form} id="milestone-form" phx-submit="save_milestone" class="space-y-3">
        <input
          type="text"
          id={@form[:label].id}
          name={@form[:label].name}
          required
          autofocus
          maxlength="200"
          placeholder="e.g. End of Chapter 3"
          value={Phoenix.HTML.Form.normalize_value("text", @form[:label].value)}
          class="w-full input input-sm font-serif"
        />

        <div class="flex gap-2">
          <button type="submit" class="btn btn-primary btn-sm">Place</button>
          <button type="button" phx-click="cancel_milestone" class="btn btn-ghost btn-sm">
            Cancel
          </button>
        </div>
      </.form>
    </section>
    """
  end

  attr :form, :any, required: true
  attr :selection, :map, required: true
  attr :type, :atom, required: true

  defp annotation_form_section(assigns) do
    ~H"""
    <section class="border-l-2 border-terracotta pl-4 py-3 mb-4 bg-paper">
      <p class="section-label text-terracotta mb-2">
        New {form_label(@type)} · page <span class="num">{@selection.page}</span>
      </p>

      <blockquote class="font-serif italic text-ink-soft text-sm border-l border-paper-2 pl-2 mb-3">
        “{@selection.text}”
      </blockquote>

      <.form for={@form} id="annotation-form" phx-submit="save_annotation" class="space-y-3">
        <textarea
          id={@form[:body].id}
          name={@form[:body].name}
          rows="3"
          required
          autofocus
          placeholder={form_placeholder(@type)}
          class="w-full textarea text-sm font-serif"
        >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>

        <input type="hidden" name={@form[:visibility].name} value="workspace" />
        <label class="flex items-center gap-2 cursor-pointer select-none">
          <input
            type="checkbox"
            id={@form[:visibility].id}
            name={@form[:visibility].name}
            value="private"
            checked={visibility_private?(@form[:visibility].value)}
            class="checkbox checkbox-xs"
          />
          <span class="section-label">Private — only you</span>
        </label>

        <div class="flex gap-2">
          <button type="submit" class="btn btn-primary btn-sm">Save</button>
          <button type="button" phx-click="cancel_annotation" class="btn btn-ghost btn-sm">
            Cancel
          </button>
        </div>
      </.form>
    </section>
    """
  end

  # Slice 16.4 — quiet line-drawn empty state. Two flavours: the
  # "no annotations yet" prompt that nudges the reader to highlight a
  # passage, and the "no comments/questions/puzzles on this book yet"
  # variant that sits under the filter chips when the active filter
  # produces nothing. SVG only — no emoji per CLAUDE.md §5.4.
  attr :kind, :atom, values: [:no_annotations, :no_filtered, :no_page_notes], required: true
  attr :label, :string, default: nil

  defp empty_state(assigns) do
    ~H"""
    <section
      role="note"
      aria-live="polite"
      class="flex flex-col items-center text-center px-4 py-10 gap-4"
    >
      <svg
        viewBox="0 0 96 96"
        aria-hidden="true"
        focusable="false"
        class="w-20 h-20 text-ink-soft/60"
        fill="none"
        stroke="currentColor"
        stroke-width="1"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path d="M22 18 L22 80" />
        <path d="M22 18 C 38 12, 50 12, 60 18 L 60 80 C 50 74, 38 74, 22 80 Z" />
        <path d="M28 30 L 54 30" />
        <path d="M28 38 L 50 38" />
        <path d="M28 46 L 52 46" />
        <path d="M70 28 L 80 28" stroke="currentColor" />
        <path d="M70 36 L 78 36" />
        <path d="M70 44 L 80 44" />
        <circle cx="68" cy="56" r="2" fill="currentColor" stroke="none" />
      </svg>
      <p class="font-serif italic text-ink-soft text-sm leading-relaxed max-w-[18rem]">
        <%= case @kind do %>
          <% :no_annotations -> %>
            No notes yet. Highlight a passage in the page to leave the first one.
          <% :no_filtered -> %>
            No {@label} on this book yet. Try a different filter, or start one.
          <% :no_page_notes -> %>
            No notes on {@label} yet. Switch to "All" or highlight a passage to start one.
        <% end %>
      </p>
    </section>
    """
  end

  attr :insight, :any, required: true

  defp group_lens_card(assigns) do
    ~H"""
    <div class="mb-3 rounded-md border-l-[3px] border-amber-400 bg-amber-50 px-4 py-3">
      <div class="flex items-center justify-between mb-2">
        <span class="section-label text-amber-700 tracking-widest">
          GROUP LENS · PAGE {@insight.page_number}
        </span>
        <span class="section-label text-amber-600">
          <span class="num">{length(@insight.contributor_ids)}</span> readers
        </span>
      </div>
      <p class="font-serif text-sm text-ink leading-relaxed">{@insight.synthesis}</p>
    </div>
    """
  end

  attr :type, :atom, required: true
  attr :label, :string, required: true
  attr :count, :integer, default: 0
  attr :active?, :boolean, default: false

  defp filter_chip(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="set_filter"
      phx-value-type={to_string(@type)}
      aria-pressed={to_string(@active?)}
      class={[
        "font-mono text-[10px] uppercase tracking-widest px-2 py-1 rounded-sm border transition-colors cursor-pointer",
        if(@active?,
          do: "bg-terracotta text-paper border-terracotta",
          else:
            "bg-paper text-ink-soft border-paper-2 hover:border-terracotta/40 hover:text-terracotta"
        )
      ]}
    >
      {@label}
      <span class="num ml-1 opacity-70">{@count}</span>
    </button>
    """
  end

  # Scope tabs above the filter chips. "All" shows every annotation in the
  # book; "Page" narrows to the current focal page (the topmost page in the
  # viewport, fed by the canvas's `pages_visible` event). The user picks
  # which lens they want — we don't auto-switch as they scroll.
  attr :scope, :atom, required: true
  attr :label, :string, required: true
  attr :count, :integer, default: 0
  attr :active?, :boolean, default: false

  defp scope_tab(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="set_scope"
      phx-value-scope={to_string(@scope)}
      aria-pressed={to_string(@active?)}
      class={[
        "font-mono text-[11px] uppercase tracking-widest px-3 py-1.5 transition-colors cursor-pointer",
        "border-b-2",
        if(@active?,
          do: "text-ink border-terracotta",
          else: "text-ink-soft border-transparent hover:text-terracotta"
        )
      ]}
    >
      {@label}
      <span class="num ml-1 opacity-70">{@count}</span>
    </button>
    """
  end

  def handle_event(
        "text_selected",
        %{"text" => text, "page" => page, "rect" => rect, "type" => "milestone"},
        socket
      ) do
    # Slice 12 (revised, take 2) — admin-only branch. The selection menu's
    # "+ Place milestone" option lands here. Open a label form in the
    # margin pre-filled with the selected text, and stash the rect/page
    # so `save_milestone` can place it without a second round-trip.
    actor = socket.assigns.current_user

    cond do
      not socket.assigns.is_admin? ->
        {:noreply, socket}

      not is_map(rect) ->
        {:noreply, socket}

      true ->
        position = position_from_rect(rect)
        placement = %{page: page, position: position}

        form =
          Progress.MilestoneMarker
          |> AshPhoenix.Form.for_create(:create_milestone,
            actor: actor,
            params: %{
              "resource_id" => socket.assigns.resource.id,
              "page_number" => page,
              "position" => position,
              "label" => default_milestone_label(text)
            }
          )
          |> to_form()

        {:noreply,
         socket
         |> assign(:milestone_pending_placement, placement)
         |> assign(:milestone_form, form)
         # Close any open annotation chrome so the two forms don't fight
         # for the margin column.
         |> assign(:selection, nil)
         |> assign(:annotation_form, nil)
         |> assign(:annotation_form_type, nil)}
    end
  end

  # Slice 11: "Ask AI" from the floating selection menu. Opens the same form
  # flow as comment/question, but the save handler dispatches AnswerWorker
  # after creating the annotation. We use annotation_form_type :ai internally;
  # the DB action is :create_question.
  def handle_event(
        "text_selected",
        %{"text" => text, "page" => page, "rect" => rect, "type" => "ai"},
        socket
      ) do
    actor = socket.assigns.current_user

    form =
      Annotations.Annotation
      |> AshPhoenix.Form.for_create(:create_question,
        actor: actor,
        params: %{
          "resource_id" => socket.assigns.resource.id,
          "page_number" => page,
          "rect" => rect,
          "text" => text,
          "body" => "",
          "visibility" => "workspace"
        }
      )
      |> to_form()

    {:noreply,
     socket
     |> assign(:selection, %{text: text, page: page, rect: rect})
     |> assign(:annotation_form, form)
     |> assign(:annotation_form_type, :ai)
     |> assign(:milestone_form, nil)
     |> assign(:milestone_pending_placement, nil)}
  end

  def handle_event(
        "text_selected",
        %{"text" => text, "page" => page, "rect" => rect} = params,
        socket
      ) do
    type = parse_create_type(Map.get(params, "type"))
    action = action_for(type)

    selection = %{
      text: text,
      page: page,
      rect: rect
    }

    form =
      Annotations.Annotation
      |> AshPhoenix.Form.for_create(action,
        actor: socket.assigns.current_user,
        params: %{
          "resource_id" => socket.assigns.resource.id,
          "page_number" => page,
          "rect" => rect,
          "text" => text,
          "body" => "",
          "visibility" => "workspace"
        }
      )
      |> to_form()

    {:noreply,
     socket
     |> assign(:selection, selection)
     |> assign(:annotation_form, form)
     |> assign(:annotation_form_type, type)
     # If the admin had a milestone form open, close it — the new
     # annotation flow takes priority.
     |> assign(:milestone_form, nil)
     |> assign(:milestone_pending_placement, nil)}
  end

  def handle_event("cancel_annotation", _params, socket) do
    {:noreply,
     socket
     |> assign(:selection, nil)
     |> assign(:annotation_form, nil)
     |> assign(:annotation_form_type, nil)}
  end

  # Slice 16.6 — Escape closes whatever open chrome is in the margin
  # column. Order matters: the canvas's selection menu / milestone popover
  # are handled inside the Svelte component, so by the time we get here
  # the user has either no canvas chrome open, or both. We close the LV
  # forms in priority order: annotation form > milestone form > expanded
  # thread, so a single Escape unwinds one level at a time.
  def handle_event("reader_keydown", %{"key" => "Escape"}, socket) do
    cond do
      socket.assigns.annotation_form ->
        {:noreply,
         socket
         |> assign(:selection, nil)
         |> assign(:annotation_form, nil)
         |> assign(:annotation_form_type, nil)}

      socket.assigns.milestone_form ->
        {:noreply,
         socket
         |> assign(:milestone_form, nil)
         |> assign(:milestone_pending_placement, nil)}

      socket.assigns.expanded_thread_id ->
        {:noreply,
         socket
         |> assign(:expanded_thread_id, nil)
         |> assign(:thread_replies, [])
         |> assign(:reply_form, nil)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("reader_keydown", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_milestone", _params, socket) do
    {:noreply,
     socket
     |> assign(:milestone_form, nil)
     |> assign(:milestone_pending_placement, nil)}
  end

  # Slice 12 (revised, take 2): milestone placement now lives in the
  # selection menu next to comment/question/puzzle. The Svelte canvas
  # ships `text_selected` with `type: "milestone"` (admin-only), the LV
  # opens a label form in the margin pre-filled with the selected text
  # (matching Add Comment's pattern), and `save_milestone` creates the
  # milestone using the cached selection rect for position.
  def handle_event("save_milestone", %{"form" => params}, socket) do
    actor = socket.assigns.current_user
    placement = socket.assigns.milestone_pending_placement
    label = Map.get(params, "label", "")

    cond do
      is_nil(placement) ->
        {:noreply, socket}

      not socket.assigns.is_admin? ->
        {:noreply,
         socket
         |> assign(:milestone_form, nil)
         |> assign(:milestone_pending_placement, nil)}

      true ->
        case Progress.create_milestone(
               socket.assigns.resource.id,
               placement.page,
               placement.position,
               label,
               actor: actor,
               load: [:created_by, :stamp_count, stamps: [:user]]
             ) do
          {:ok, _milestone} ->
            {:noreply,
             socket
             |> refresh_milestones()
             |> assign(:milestone_form, nil)
             |> assign(:milestone_pending_placement, nil)
             |> put_flash(:info, "Milestone placed.")}

          {:error, %AshPhoenix.Form{} = form} ->
            {:noreply, assign(socket, :milestone_form, form)}

          {:error, error} ->
            {:noreply,
             put_flash(socket, :error, "Couldn't place milestone: #{format_error(error)}")}
        end
    end
  end

  # Slice 13: a reader confirmed a stamp from the canvas popover. Run the
  # Ash action under the actor (so the workspace-member policy gates), then
  # refresh the milestone list — same pathway as the PubSub handler — so
  # the canvas's `rubber_stamps[]` and the margin panel both update.
  def handle_event("apply_stamp", %{"milestone_id" => milestone_id}, socket) do
    actor = socket.assigns.current_user

    case Progress.apply_stamp(milestone_id, nil, actor: actor) do
      {:ok, _stamp} ->
        {:noreply,
         socket
         |> refresh_milestones()
         |> put_flash(:info, "Stamped.")}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        if Enum.any?(errors, &match?(%Ash.Error.Changes.InvalidAttribute{}, &1)) or
             Enum.any?(errors, &has_unique_violation?/1) do
          # Already stamped — silently no-op so a double click doesn't surface
          # a scary error. The popover will reflect the existing stamp on the
          # next prop pass.
          {:noreply, refresh_milestones(socket)}
        else
          {:noreply, put_flash(socket, :error, "Couldn't stamp: #{format_error_list(errors)}")}
        end

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Couldn't stamp: #{format_error(error)}")}
    end
  end

  # Slice 15a (revert): Svelte's IntersectionObserver reports which pages
  # intersect the viewport. The canvas also includes a `primary` field —
  # the page with the largest visual overlap with the actual viewport
  # (the rootMargin-expanded `first` is too generous: when a sliver of
  # the previous page sits within the 1000px buffer above the viewport,
  # `first` lands on it even though the reader is looking at the next
  # page). We use `primary` as `:focal_page`; the margin column then
  # highlights cards on that page (Slice 15a) and the "Page" scope tab
  # filters to it.
  # PDF.js → LV: top-level outline entries flattened to {label, page}.
  # Stored as @chapters and fed to the chapter rail. Empty list when the
  # PDF has no outline; the rail falls back to roman-numeral placeholders.
  def handle_event("outline_loaded", %{"chapters" => chapters}, socket) do
    total_pages = socket.assigns.resource.page_count
    parsed = parse_outline_chapters(chapters, total_pages)
    {:noreply, assign(socket, :chapters, parsed)}
  end

  # Chapter rail click → ask the canvas to bring `page` into view. The
  # canvas's IntersectionObserver then reports the new visible range via
  # `pages_visible`, which updates `:focal_page` — so we don't need to
  # touch any assign here, just route the signal.
  def handle_event("chapter_clicked", %{"page" => page}, socket) do
    total_pages = socket.assigns.resource.page_count

    case parse_page_in_range(page, total_pages) do
      {:ok, page} -> {:noreply, push_event(socket, "scroll_to_page", %{page: page})}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("pages_visible", %{"first" => first} = params, socket) do
    primary = Map.get(params, "primary", first)
    total_pages = socket.assigns.resource.page_count
    new_focal = primary |> to_int() |> max(1) |> min(total_pages)

    if new_focal == socket.assigns.focal_page do
      {:noreply, socket}
    else
      actor = socket.assigns.current_user
      resource_id = socket.assigns.resource.id

      Phoenix.PubSub.broadcast_from!(
        Studysync.PubSub,
        self(),
        AnnotationsPubSub.topic(resource_id),
        {:reader_page, actor.id, to_string(actor.email), new_focal}
      )

      {:noreply, assign(socket, :focal_page, new_focal)}
    end
  end

  def handle_event("set_filter", %{"type" => type}, socket) do
    {:noreply, assign(socket, :filter_type, parse_filter_type(type))}
  end

  def handle_event("set_scope", %{"scope" => scope}, socket) do
    {:noreply, assign(socket, :filter_scope, parse_filter_scope(scope))}
  end

  # Margin → PDF: clicking a margin note focuses the annotation. The Svelte
  # component reacts to the new `active_annotation_id` prop by scrolling its
  # source page into view and pulsing the marker.
  def handle_event("select_annotation", %{"id" => id}, socket) do
    if socket.assigns.active_annotation_id == id do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :active_annotation_id, id)}
    end
  end

  # PDF → Margin: clicking a marker in the canvas focuses the annotation and
  # asks the margin column to scroll the matching card into view. Also
  # realigns `:focal_page` to that annotation's page so the focal-page
  # background highlight follows immediately rather than waiting for the
  # next IO tick.
  def handle_event("annotation_clicked", %{"id" => id}, socket) do
    if socket.assigns.active_annotation_id == id do
      {:noreply, push_event(socket, "scroll_to_margin_note", %{id: id})}
    else
      page = annotation_page(socket.assigns.annotations, id)

      {:noreply,
       socket
       |> assign(:active_annotation_id, id)
       |> then(fn s -> if page, do: assign(s, :focal_page, page), else: s end)
       |> push_event("scroll_to_margin_note", %{id: id})}
    end
  end

  # Toggle the thread under a margin note. Loads replies on expand, clears
  # on collapse. Re-clicking the currently-expanded note collapses it.
  def handle_event("toggle_thread", %{"id" => id}, socket) do
    actor = socket.assigns.current_user
    prev = socket.assigns.expanded_thread_id

    socket =
      if prev == id do
        socket
        |> assign(:expanded_thread_id, nil)
        |> assign(:thread_replies, [])
        |> assign(:reply_form, nil)
      else
        socket
        |> assign(:expanded_thread_id, id)
        |> assign(:thread_replies, load_thread(id, actor))
        |> assign(:reply_form, build_reply_form(id, actor))
      end

    {:noreply, socket}
  end

  def handle_event("submit_reply", %{"form" => params}, socket) do
    actor = socket.assigns.current_user
    annotation_id = socket.assigns.expanded_thread_id
    body = Map.get(params, "body", "")

    case Annotations.reply(annotation_id, body, actor: actor, load: [:user]) do
      {:ok, reply} ->
        {:noreply,
         socket
         |> bump_reply_count(annotation_id)
         |> append_reply_if_open(reply)
         |> assign(:reply_form, build_reply_form(annotation_id, actor))}

      {:error, %AshPhoenix.Form{} = form} ->
        {:noreply, assign(socket, :reply_form, form)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Couldn't reply: #{format_error(error)}")}
    end
  end

  def handle_event("save_annotation", %{"form" => params}, socket) do
    actor = socket.assigns.current_user
    selection = socket.assigns.selection
    type = socket.assigns.annotation_form_type || :comment

    body = Map.get(params, "body", "")
    visibility = parse_visibility(Map.get(params, "visibility"))

    # Slice 15.5 — observe end-to-end annotation creation latency. The
    # `:telemetry.span` straddles the Ash action so the timing includes
    # changes, policy checks, the DB insert, and the after_action broadcast.
    result =
      :telemetry.span(
        [:studysync, :annotations, :create],
        %{type: type, resource_id: socket.assigns.resource.id, visibility: visibility},
        fn ->
          result =
            apply(Annotations, create_fun_for(type), [
              socket.assigns.resource.id,
              selection.page,
              selection.rect,
              selection.text,
              body,
              %{visibility: visibility},
              [actor: actor, load: [:user, :reply_count]]
            ])

          {result,
           %{
             type: type,
             resource_id: socket.assigns.resource.id,
             outcome: outcome_tag(result)
           }}
        end
      )

    case result do
      {:ok, annotation} ->
        socket =
          socket
          |> insert_annotation(annotation)
          |> assign(:selection, nil)
          |> assign(:annotation_form, nil)
          |> assign(:annotation_form_type, nil)

        # Slice 11: dispatch AI worker and track loading state.
        socket =
          if type == :ai do
            %{"annotation_id" => annotation.id}
            |> AnswerWorker.new()
            |> Oban.insert!()

            assign(
              socket,
              :ai_pending_annotation_ids,
              MapSet.put(socket.assigns.ai_pending_annotation_ids, annotation.id)
            )
          else
            socket
          end

        {:noreply, put_flash(socket, :info, save_flash(type))}

      {:error, %AshPhoenix.Form{} = form} ->
        {:noreply, assign(socket, :annotation_form, form)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Couldn't save: #{format_error(error)}")}
    end
  end

  def handle_event("show_sprint_form", _params, socket) do
    {:noreply, assign(socket, :show_sprint_form, true)}
  end

  def handle_event("cancel_sprint_form", _params, socket) do
    {:noreply, assign(socket, :show_sprint_form, false)}
  end

  def handle_event(
        "start_sprint",
        %{
          "start_page" => start_page,
          "end_page" => end_page,
          "duration_minutes" => duration_minutes
        },
        socket
      ) do
    actor = socket.assigns.current_user
    resource = socket.assigns.resource

    with {sp, ""} <- Integer.parse(start_page),
         {ep, ""} <- Integer.parse(end_page),
         {dur, ""} <- Integer.parse(duration_minutes),
         true <- sp >= 1 and ep >= sp and dur >= 1 and dur <= 120 do
      case Sprints.start_sprint(
             resource.id,
             socket.assigns.workspace_id,
             sp,
             ep,
             dur,
             actor: actor
           ) do
        {:ok, _sprint} ->
          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not start sprint.")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid sprint parameters.")}
    end
  end

  def handle_event("join_sprint", %{"sprint_id" => sprint_id}, socket) do
    actor = socket.assigns.current_user

    case Sprints.join_sprint(sprint_id, actor: actor) do
      {:ok, _member} ->
        {:noreply, assign(socket, :sprint_member?, true)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not join sprint.")}
    end
  end

  def handle_event("dismiss_compare_notes", _params, socket) do
    {:noreply,
     socket
     |> assign(:compare_notes, nil)
     |> assign(:active_sprint, nil)}
  end

  # PubSub: a peer just created an annotation on this resource. Refetch so
  # we run our own actor's read policies, then patch the stream + sidebar.
  def handle_info({:annotation_created, %{id: id, resource_id: resource_id}}, socket) do
    if resource_id != socket.assigns.resource.id do
      {:noreply, socket}
    else
      case Annotations.get_annotation(id,
             actor: socket.assigns.current_user,
             load: [:user, :reply_count]
           ) do
        {:ok, annotation} -> {:noreply, insert_annotation(socket, annotation)}
        # Forbidden/private/deleted — quietly ignore.
        _ -> {:noreply, socket}
      end
    end
  end

  # PubSub: a peer (or the AI worker) replied to an annotation. Always bump
  # the badge; only fetch the reply body if the matching thread is open.
  # Slice 11: also clears ai_pending_annotation_ids when a reply arrives so
  # the loading indicator dismisses as soon as the AI responds.
  def handle_info(
        {:reply_created, %{id: id, annotation_id: annotation_id, resource_id: resource_id}},
        socket
      ) do
    if resource_id != socket.assigns.resource.id do
      {:noreply, socket}
    else
      socket = bump_reply_count(socket, annotation_id)

      socket =
        assign(
          socket,
          :ai_pending_annotation_ids,
          MapSet.delete(socket.assigns.ai_pending_annotation_ids, annotation_id)
        )

      if socket.assigns.expanded_thread_id == annotation_id do
        case fetch_reply(id, socket.assigns.current_user) do
          {:ok, reply} -> {:noreply, append_reply_if_open(socket, reply)}
          _ -> {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end
  end

  # Slice 18 — chat: forward broadcast messages to the live_component, which
  # owns the message stream + unread counter. The sender doesn't receive its
  # own broadcast (broadcast_from!), so this only fires for peer messages.
  def handle_info({:chat_message, %Studysync.Chat.Message{} = message}, socket) do
    send_update(StudysyncWeb.PdfLive.ChatPanel,
      id: @chat_panel_id,
      new_message: message
    )

    {:noreply, socket}
  end

  # Slice 18.8 — presence diffs on the chat topic. Recompute the headcount
  # and forward to the panel; ignore diffs from any other topic the LV
  # might be subscribed to.
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", topic: topic},
        socket
      ) do
    chat_topic = ChatPubSub.topic(socket.assigns.resource.id)

    if topic == chat_topic do
      here_now = chat_here_now(socket.assigns.resource.id)
      readers_here = readers_here_list(socket.assigns.resource.id, socket.assigns.current_user)

      send_update(StudysyncWeb.PdfLive.ChatPanel,
        id: @chat_panel_id,
        here_now: here_now
      )

      {:noreply,
       socket
       |> assign(:chat_here_now, here_now)
       |> assign(:readers_here, readers_here)}
    else
      {:noreply, socket}
    end
  end

  # PubSub: a peer just stamped a milestone. Refetch through Ash so per-actor
  # read policies stay honest, then refresh the milestone-derived assigns.
  def handle_info(
        {:stamp_applied, %{milestone_id: milestone_id, resource_id: resource_id}},
        socket
      ) do
    if resource_id != socket.assigns.resource.id do
      {:noreply, socket}
    else
      _ = milestone_id
      {:noreply, refresh_milestones(socket)}
    end
  end

  # PubSub: the AI finished generating a GROUP LENS insight for a page on this
  # resource. Prepend to the list so it appears without a full reload.
  def handle_info({:collective_insight_ready, insight}, socket) do
    if insight.resource_id != socket.assigns.resource.id do
      {:noreply, socket}
    else
      insights = [insight | socket.assigns.collective_insights]
      {:noreply, assign(socket, :collective_insights, insights)}
    end
  end

  # Sprint PubSub handlers

  def handle_info({:sprint_started, sprint}, socket) do
    if sprint.resource_id != socket.assigns.resource.id do
      {:noreply, socket}
    else
      schedule_sprint_tick()
      actor = socket.assigns.current_user
      sprint_member? = Sprints.sprint_member?(sprint, actor.id)

      {:noreply,
       socket
       |> assign(:active_sprint, sprint)
       |> assign(:sprint_member?, sprint_member?)
       |> assign(:sprint_countdown, sprint_countdown(sprint))
       |> assign(:show_sprint_form, false)}
    end
  end

  def handle_info({:sprint_joined, sprint}, socket) do
    if sprint.resource_id != socket.assigns.resource.id do
      {:noreply, socket}
    else
      actor = socket.assigns.current_user
      sprint_member? = Sprints.sprint_member?(sprint, actor.id)

      {:noreply,
       socket
       |> assign(:active_sprint, sprint)
       |> assign(:sprint_member?, sprint_member?)}
    end
  end

  def handle_info({:sprint_ended, sprint}, socket) do
    if sprint.resource_id != socket.assigns.resource.id do
      {:noreply, socket}
    else
      sprint_with_members =
        case Ash.get(Studysync.Sprints.Sprint, sprint.id,
               load: [members: []],
               authorize?: false
             ) do
          {:ok, s} -> s
          _ -> sprint
        end

      notes = Sprints.compare_notes(sprint_with_members)

      {:noreply,
       socket
       |> assign(:active_sprint, sprint_with_members)
       |> assign(:sprint_member?, false)
       |> assign(:sprint_countdown, nil)
       |> assign(:compare_notes, notes)}
    end
  end

  def handle_info(:sprint_tick, socket) do
    case socket.assigns.active_sprint do
      %{status: :active} = sprint ->
        schedule_sprint_tick()
        {:noreply, assign(socket, :sprint_countdown, sprint_countdown(sprint))}

      _ ->
        {:noreply, socket}
    end
  end

  # Page presence — another reader moved to a new page.
  def handle_info({:reader_page, user_id, email, page}, socket) do
    updated =
      socket.assigns.page_readers
      |> Enum.map(fn {p, readers} -> {p, Enum.reject(readers, &(&1.user_id == user_id))} end)
      |> Enum.reject(fn {_p, readers} -> readers == [] end)
      |> Map.new()
      |> Map.update(page, [%{user_id: user_id, email: email}], fn readers ->
        if Enum.any?(readers, &(&1.user_id == user_id)),
          do: readers,
          else: [%{user_id: user_id, email: email} | readers]
      end)

    {:noreply, assign(socket, :page_readers, updated)}
  end

  # Page presence — a reader closed the PDF; remove them from all pages.
  def handle_info({:reader_left, user_id}, socket) do
    updated =
      socket.assigns.page_readers
      |> Enum.map(fn {p, readers} -> {p, Enum.reject(readers, &(&1.user_id == user_id))} end)
      |> Enum.reject(fn {_p, readers} -> readers == [] end)
      |> Map.new()

    {:noreply, assign(socket, :page_readers, updated)}
  end

  defp refresh_milestones(socket) do
    actor = socket.assigns.current_user
    milestones = load_milestones(socket.assigns.resource.id, actor)
    assign(socket, :milestones, milestones)
  end

  defp has_unique_violation?(%Ash.Error.Changes.InvalidChanges{message: msg})
       when is_binary(msg) do
    String.contains?(String.downcase(msg), "already")
  end

  defp has_unique_violation?(%{message: msg}) when is_binary(msg) do
    String.contains?(String.downcase(msg), "already")
  end

  defp has_unique_violation?(_), do: false

  defp format_error_list(errors) do
    Enum.map_join(errors, ", ", fn
      %{message: msg} when is_binary(msg) -> msg
      other -> inspect(other)
    end)
  end

  # Slice 15a (revert): insert a freshly-created annotation into the
  # whole-book list, kept ordered by (page, inserted_at). Skips if we've
  # already seen the id (PubSub double-fire from our own create).
  defp insert_annotation(socket, annotation) do
    annotations = socket.assigns.annotations

    if Enum.any?(annotations, &(&1.id == annotation.id)) do
      socket
    else
      assign(
        socket,
        :annotations,
        sort_annotations([annotation | annotations])
      )
    end
  end

  defp bump_reply_count(socket, annotation_id) do
    annotations =
      Enum.map(socket.assigns.annotations, fn a ->
        if a.id == annotation_id, do: %{a | reply_count: a.reply_count + 1}, else: a
      end)

    assign(socket, :annotations, annotations)
  end

  defp append_reply_if_open(socket, reply) do
    cond do
      socket.assigns.expanded_thread_id != reply.annotation_id ->
        socket

      Enum.any?(socket.assigns.thread_replies, &(&1.id == reply.id)) ->
        socket

      true ->
        assign(socket, :thread_replies, socket.assigns.thread_replies ++ [reply])
    end
  end

  defp fetch_reply(id, actor) do
    Ash.get(Annotations.AnnotationComment, id, actor: actor, load: [:user])
  end

  # Whole-book sort: page first, inserted_at second. Stable for a given
  # (page, inserted_at) pair so per-page numbering is deterministic.
  defp sort_annotations(annotations) do
    Enum.sort_by(annotations, &{&1.page_number, &1.inserted_at}, fn
      {p1, t1}, {p2, t2} ->
        cond do
          p1 < p2 -> true
          p1 > p2 -> false
          true -> DateTime.compare(t1, t2) != :gt
        end
    end)
  end

  # Look up an annotation's page from the loaded list. Falls back to nil
  # for ids the actor can't read or that haven't reached us yet — caller
  # treats that as "leave focal_page alone."
  defp annotation_page(annotations, id) do
    case Enum.find(annotations, &(&1.id == id)) do
      %{page_number: page} -> page
      _ -> nil
    end
  end

  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_binary(n), do: String.to_integer(n)

  defp load_thread(annotation_id, actor) do
    Annotations.list_replies!(
      actor: actor,
      query: [filter: [annotation_id: annotation_id], sort: [inserted_at: :asc]],
      load: [:user]
    )
  end

  defp build_reply_form(annotation_id, actor) do
    Annotations.AnnotationComment
    |> AshPhoenix.Form.for_create(:reply,
      actor: actor,
      params: %{"annotation_id" => annotation_id, "body" => ""}
    )
    |> to_form()
  end

  # Per-page numbered markers for the canvas. Body/text never crosses the
  # wire to Svelte — the canvas only needs marker geometry.
  defp svelte_annotations(annotations) do
    annotations
    |> Enum.group_by(& &1.page_number)
    |> Enum.flat_map(fn {_page, page_annotations} ->
      page_annotations
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> Enum.with_index(1)
      |> Enum.map(fn {a, idx} ->
        %{id: a.id, number: idx, page: a.page_number, rect: a.rect, type: a.type, text: a.text}
      end)
    end)
  end

  # Page presence: flatten the page → readers map into a list the Svelte
  # canvas can render as ambient "N people here" badges.
  defp svelte_page_readers(page_readers) do
    page_readers
    |> Enum.map(fn {page, readers} ->
      %{
        page: page,
        count: length(readers),
        emails: Enum.map(readers, & &1.email)
      }
    end)
  end

  # Filtered view of the full annotation list, with a per-page
  # `:display_number` precomputed for the margin card's footnote marker.
  # Used by the `:for` over `@annotations` in the margin column.
  defp visible_annotations(annotations, filter_type) do
    annotations
    |> Enum.filter(&visible_under_filter?(&1, filter_type))
    |> Enum.group_by(& &1.page_number)
    |> Enum.flat_map(fn {_page, page_annotations} ->
      page_annotations
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> Enum.with_index(1)
      |> Enum.map(fn {a, idx} -> Map.put(a, :display_number, idx) end)
    end)
    |> Enum.sort_by(&{&1.page_number, &1.inserted_at}, fn
      {p1, t1}, {p2, t2} ->
        cond do
          p1 < p2 -> true
          p1 > p2 -> false
          true -> DateTime.compare(t1, t2) != :gt
        end
    end)
  end

  defp load_collective_insights(resource_id) do
    CollectiveInsight
    |> Ash.Query.filter(resource_id == ^resource_id)
    |> Ash.Query.sort(page_number: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp load_milestones(resource_id, actor) do
    Progress.list_milestones!(
      actor: actor,
      query: [filter: [resource_id: resource_id], sort: [page_number: :asc, inserted_at: :asc]],
      load: [:created_by, :stamp_count, stamps: [:user]]
    )
  end

  defp svelte_milestones(milestones) do
    Enum.map(milestones, fn m ->
      %{
        id: m.id,
        page: m.page_number,
        position: m.position,
        label: m.label
      }
    end)
  end

  # Flatten stamps across milestones into the canvas-shaped list. Email is
  # included so the popover avatar cluster doesn't need a second round-trip.
  defp svelte_stamps(milestones) do
    Enum.flat_map(milestones, fn m ->
      Enum.map(m.stamps, fn stamp ->
        %{
          id: stamp.id,
          milestone_id: m.id,
          user_id: stamp.user_id,
          email: stamper_email(stamp)
        }
      end)
    end)
  end

  defp stamper_email(%{user: %{email: email}}) when not is_nil(email), do: to_string(email)
  defp stamper_email(_), do: nil

  # Workspace member count — denominator for the per-milestone "X / N readers"
  # label in the canvas popover. Bypasses Ash on read because we're computing
  # a count to show *the actor*, not exposing membership data, and the actor
  # is asking about their own workspace.
  defp count_workspace_members(workspace_id) do
    Studysync.Workspaces.Membership
    |> Ash.Query.filter(workspace_id == ^workspace_id and status == :active)
    |> Ash.count!(authorize?: false)
  end

  defp author_email(%{user: %{email: email}}) when not is_nil(email), do: to_string(email)
  defp author_email(_), do: nil

  # Per-type filter chips above the margin column. `:all` is the default lens;
  # the per-type entries map 1:1 to the action set on Annotation.
  defp filter_chips do
    [
      %{type: :all, label: "All"},
      %{type: :comment, label: "Comments"},
      %{type: :question, label: "Questions"},
      %{type: :puzzle, label: "Puzzles"}
    ]
  end

  # Filter counts come from the lightweight index, not the loaded set, so
  # they stay accurate even when only a subset of pages is hydrated
  # (Slice 15.1).
  defp filtered_count(index, :all), do: length(index)

  defp filtered_count(index, type) when type in [:comment, :question, :puzzle] do
    Enum.count(index, &(&1.type == type))
  end

  defp chip_count(index, :all), do: length(index)
  defp chip_count(index, type), do: filtered_count(index, type)

  defp visible_under_filter?(_annotation, :all), do: true
  defp visible_under_filter?(%{type: type}, type), do: true
  defp visible_under_filter?(_, _), do: false

  defp parse_filter_type("all"), do: :all
  defp parse_filter_type("comment"), do: :comment
  defp parse_filter_type("question"), do: :question
  defp parse_filter_type("puzzle"), do: :puzzle
  defp parse_filter_type(_), do: :all

  defp parse_filter_scope("page"), do: :page
  defp parse_filter_scope(_), do: :all

  # Sanitize the outline payload from the canvas: keep only entries with a
  # non-empty label and an in-range page, normalise to a flat list of maps,
  # and cap the count so a pathological 500-entry TOC can't bloat the rail.
  defp parse_outline_chapters(chapters, total_pages) when is_list(chapters) do
    chapters
    |> Enum.flat_map(fn
      %{"label" => label, "page" => page} ->
        with {:ok, label} <- normalize_label(label),
             {:ok, page} <- normalize_page(page, total_pages) do
          [%{label: label, page: page}]
        else
          _ -> []
        end

      _ ->
        []
    end)
    |> Enum.take(40)
  end

  defp parse_outline_chapters(_, _), do: []

  defp normalize_label(label) when is_binary(label) do
    case String.trim(label) do
      "" -> :error
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_label(_), do: :error

  defp normalize_page(page, total_pages) do
    n = to_int(page)
    if n >= 1 and n <= max(total_pages, 1), do: {:ok, n}, else: :error
  rescue
    _ -> :error
  end

  defp parse_page_in_range(page, total_pages), do: normalize_page(page, total_pages)

  # Narrow the annotation list by the active scope. `:all` is the
  # whole-book lens; `:page` clips to the focal page (the topmost page
  # currently in the viewport). When the focal page is unset, the page
  # lens shows nothing — the user hasn't scrolled to a page yet.
  defp scoped_annotations(annotations, :all, _focal), do: annotations
  defp scoped_annotations(_annotations, :page, nil), do: []

  defp scoped_annotations(annotations, :page, focal_page) do
    Enum.filter(annotations, &(&1.page_number == focal_page))
  end

  defp page_scope_count(_annotations, nil), do: 0

  defp page_scope_count(annotations, focal_page) do
    Enum.count(annotations, &(&1.page_number == focal_page))
  end

  defp focal_page_label(nil), do: "this page"
  defp focal_page_label(page) when is_integer(page), do: "page #{page}"

  defp parse_create_type("question"), do: :question
  defp parse_create_type("puzzle"), do: :puzzle
  defp parse_create_type(_), do: :comment

  # Anchor the milestone at the top-left of the selection rect — the
  # natural reading entry point of the highlighted phrase. Falls back to
  # 0/0 if a coordinate is missing.
  defp position_from_rect(%{"x" => x, "y" => y}) when is_number(x) and is_number(y),
    do: %{"x" => x, "y" => y}

  defp position_from_rect(rect) when is_map(rect) do
    %{"x" => Map.get(rect, "x", 0), "y" => Map.get(rect, "y", 0)}
  end

  # The selected text is the most useful default label. Trim and cap at
  # 200 chars (the milestone label attribute's hard limit) so a long
  # selection doesn't break the create action.
  defp default_milestone_label(text) when is_binary(text) do
    text |> String.trim() |> String.slice(0, 200)
  end

  defp default_milestone_label(_), do: ""

  # Slice 14: visibility comes off the form as either "private" (checkbox
  # ticked) or "workspace" (the hidden default the unchecked box reveals).
  # Anything else is treated as `:workspace` so we never silently widen access.
  defp parse_visibility("private"), do: :private
  defp parse_visibility(_), do: :workspace

  defp visibility_private?(:private), do: true
  defp visibility_private?("private"), do: true
  defp visibility_private?(_), do: false

  defp action_for(:question), do: :create_question
  defp action_for(:puzzle), do: :create_puzzle
  defp action_for(_), do: :create_comment

  defp create_fun_for(:question), do: :create_question
  defp create_fun_for(:puzzle), do: :create_puzzle
  defp create_fun_for(_), do: :create_comment

  defp form_label(:question), do: "question"
  defp form_label(:puzzle), do: "puzzle"
  defp form_label(:ai), do: "AI query"
  defp form_label(_), do: "note"

  defp form_placeholder(:question), do: "Your question…"
  defp form_placeholder(:puzzle), do: "What's puzzling here?"
  defp form_placeholder(:ai), do: "What would you like the AI to explore? (optional)"
  defp form_placeholder(_), do: "Your note…"

  defp save_flash(:question), do: "Question saved."
  defp save_flash(:puzzle), do: "Puzzle saved."
  defp save_flash(:ai), do: "AI is thinking…"
  defp save_flash(_), do: "Note saved."

  defp filter_label(:comment), do: "comments"
  defp filter_label(:question), do: "questions"
  defp filter_label(:puzzle), do: "puzzles"
  defp filter_label(_), do: "notes"

  defp format_error(%Ash.Error.Forbidden{}), do: "Not allowed."

  defp format_error(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.map_join(", ", fn
      %{message: msg} -> msg
      other -> inspect(other)
    end)
  end

  defp format_error(other), do: inspect(other)

  defp outcome_tag({:ok, _}), do: :ok
  defp outcome_tag({:error, _}), do: :error
  defp outcome_tag(_), do: :unknown

  # ── Sprint helpers ────────────────────────────────────────────────────────────

  defp schedule_sprint_tick do
    Process.send_after(self(), :sprint_tick, 1_000)
  end

  defp sprint_countdown(nil), do: nil
  defp sprint_countdown(%{status: :ended}), do: nil

  defp sprint_countdown(%{inserted_at: inserted_at, duration_minutes: dur}) do
    expires_at = DateTime.add(inserted_at, dur * 60, :second)
    remaining = DateTime.diff(expires_at, DateTime.utc_now(), :second)

    if remaining <= 0 do
      "0:00:00"
    else
      h = div(remaining, 3600)
      m = div(rem(remaining, 3600), 60)
      s = rem(remaining, 60)

      "#{h}:#{String.pad_leading(to_string(m), 2, "0")}:#{String.pad_leading(to_string(s), 2, "0")}"
    end
  end

  # ── Sprint UI components ──────────────────────────────────────────────────────

  attr :resource, :any, required: true

  defp sprint_form_banner(assigns) do
    ~H"""
    <div class="bg-amber-50 border-b border-amber-200 px-5 py-3">
      <p class="section-label text-amber-700 mb-2">NEW SPRINT</p>
      <form phx-submit="start_sprint" class="flex flex-wrap items-end gap-3">
        <div>
          <label class="section-label text-ink-soft block mb-1">Pages</label>
          <div class="flex items-center gap-1">
            <input
              type="number"
              name="start_page"
              min="1"
              max={@resource.page_count}
              placeholder="from"
              required
              class="input input-sm w-20 font-mono"
            />
            <span class="section-label text-ink-soft">–</span>
            <input
              type="number"
              name="end_page"
              min="1"
              max={@resource.page_count}
              placeholder="to"
              required
              class="input input-sm w-20 font-mono"
            />
          </div>
        </div>
        <div>
          <label class="section-label text-ink-soft block mb-1">Duration</label>
          <select name="duration_minutes" class="select select-sm font-mono">
            <option value="5">5 min</option>
            <option value="10">10 min</option>
            <option value="15" selected>15 min</option>
            <option value="20">20 min</option>
            <option value="30">30 min</option>
          </select>
        </div>
        <div class="flex gap-2">
          <button type="submit" class="btn btn-primary btn-sm">Start</button>
          <button type="button" phx-click="cancel_sprint_form" class="btn btn-ghost btn-sm">
            Cancel
          </button>
        </div>
      </form>
    </div>
    """
  end

  attr :sprint, :any, required: true
  attr :sprint_member?, :boolean, required: true
  attr :countdown, :string, default: nil

  defp sprint_banner(assigns) do
    ~H"""
    <div class="bg-amber-50 border-b border-amber-200 px-5 py-2.5 flex items-center gap-4">
      <span class="section-label text-amber-700">SPRINT ACTIVE</span>
      <span class="section-label text-ink-soft">
        Pages <span class="num">{@sprint.start_page}</span>–<span class="num">{@sprint.end_page}</span>
      </span>
      <span class="font-mono text-sm text-amber-800 tabular-nums flex-1">{@countdown}</span>
      <button
        :if={!@sprint_member?}
        phx-click="join_sprint"
        phx-value-sprint_id={@sprint.id}
        class="btn btn-warning btn-xs"
      >
        Join sprint
      </button>
      <span :if={@sprint_member?} class="section-label text-amber-600">Joined</span>
    </div>
    """
  end

  attr :notes, :list, required: true
  attr :sprint, :any, required: true

  defp compare_notes_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-ink/40">
      <div class="bg-paper rounded-lg shadow-xl w-full max-w-4xl max-h-[80vh] flex flex-col mx-4">
        <div class="px-6 py-4 border-b border-paper-2 flex items-baseline justify-between">
          <div>
            <p class="section-label text-terracotta">SPRINT ENDED · COMPARE NOTES</p>
            <p class="font-display text-xl text-ink mt-0.5">
              Pages {@sprint && @sprint.start_page}–{@sprint && @sprint.end_page}
            </p>
          </div>
          <button
            phx-click="dismiss_compare_notes"
            class="section-label text-ink-soft hover:text-terracotta"
          >
            Close
          </button>
        </div>

        <div class="flex-1 overflow-y-auto p-6">
          <p :if={@notes == []} class="font-serif text-ink-soft italic text-center py-8">
            No annotations were created during this sprint.
          </p>

          <div :if={@notes != []} class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div :for={{_user_id, email, annotations} <- @notes} class="space-y-3">
              <p class="section-label text-terracotta">
                {email |> String.split("@") |> List.first() |> String.upcase()}
                <span class="text-ink-soft ml-1">
                  · <span class="num">{length(annotations)}</span> notes
                </span>
              </p>
              <div
                :for={ann <- annotations}
                class="border-l-2 border-paper-2 pl-3 py-1 space-y-1"
              >
                <p class="section-label text-ink-soft">
                  p. <span class="num">{ann.page_number}</span>
                </p>
                <p :if={ann.text != ""} class="font-serif text-xs italic text-ink-soft">{ann.text}</p>
                <p class="font-serif text-sm text-ink">{ann.body}</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
