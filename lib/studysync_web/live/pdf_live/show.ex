defmodule StudysyncWeb.PdfLive.Show do
  use StudysyncWeb, :live_view

  alias Studysync.Annotations
  alias Studysync.Annotations.PubSub, as: AnnotationsPubSub
  alias Studysync.Library
  alias Studysync.Progress
  alias Studysync.Workspaces

  require Ash.Query

  # Slice 15.1/15.2: how many pages around the visible range we eagerly
  # prefetch on `pages_visible`. ±1 page matches the spec ("scroll-near, one
  # page ahead/behind"). At mount, we hydrate pages 1..@initial_visible_pages
  # so the first paint isn't blank while we wait for Svelte's first
  # IntersectionObserver tick.
  @prefetch_buffer 1
  @initial_visible_pages 3

  def mount(%{"workspace_id" => workspace_id, "id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Library.get_resource(id, actor: actor, load: [:uploaded_by]) do
      {:ok, resource}
      when not is_nil(resource) and resource.workspace_id == workspace_id ->
        # Lightweight index — every annotation's marker geometry, no
        # bodies/replies. Drives Svelte markers, filter chip counts, and the
        # per-page footnote numbering (1ⁿ resets each page).
        index = Annotations.list_annotation_index(resource.id, actor: actor)

        # Initial visible range — pages 1..3 by default. Prefetch ±1 then
        # clamps to the resource. For short PDFs (≤4 pages) this loads the
        # whole book; for long PDFs only the first viewport's worth.
        initial_visible = {1, min(@initial_visible_pages, resource.page_count)}
        initial_pages = pages_in_range(initial_visible, resource.page_count)

        annotations_by_id =
          resource.id
          |> Annotations.list_annotations_for_pages(initial_pages, actor: actor)
          |> Map.new(&{&1.id, &1})

        loaded_pages = MapSet.new(initial_pages)

        milestones = load_milestones(resource.id, actor)
        is_admin? = Workspaces.actor_admin?(workspace_id, actor)
        total_readers = count_workspace_members(workspace_id)

        if connected?(socket), do: AnnotationsPubSub.subscribe(resource.id)

        socket =
          socket
          |> assign(:resource, resource)
          |> assign(:workspace_id, workspace_id)
          |> assign(:file_url, ~p"/resources/#{resource.id}/file")
          |> assign(:page_title, resource.title)
          |> assign(:annotation_index, index)
          |> assign(:annotations_by_id, annotations_by_id)
          |> assign(:loaded_pages, loaded_pages)
          |> assign(:visible_pages, initial_visible)
          |> assign(:selection, nil)
          |> assign(:annotation_form, nil)
          |> assign(:annotation_form_type, nil)
          |> assign(:active_annotation_id, nil)
          |> assign(:expanded_thread_id, nil)
          |> assign(:thread_replies, [])
          |> assign(:reply_form, nil)
          |> assign(:filter_type, :all)
          |> assign(:milestones, milestones)
          |> assign(:is_admin?, is_admin?)
          |> assign(:total_readers, total_readers)
          |> assign(:milestone_mode, false)
          |> assign(:milestone_form, nil)
          |> assign(:milestone_pending_placement, nil)

        {:ok, init_stream(socket)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Resource not found.")
         |> push_navigate(to: ~p"/workspaces/#{workspace_id}/library")}
    end
  end

  def terminate(_reason, socket) do
    if Map.get(socket.assigns, :resource) do
      AnnotationsPubSub.unsubscribe(socket.assigns.resource.id)
    end

    :ok
  end

  def render(assigns) do
    ~H"""
    <div class="flex h-screen w-full bg-paper text-ink overflow-hidden">
      <.chapter_rail />

      <main class="flex-1 min-w-0 flex flex-col">
        <header class="flex items-baseline justify-between border-b border-paper-2 px-8 py-4 gap-4">
          <div class="min-w-0">
            <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft">
              <.link
                navigate={~p"/workspaces/#{@workspace_id}/library"}
                class="hover:text-terracotta"
              >
                Library
              </.link>
              <span> ·  Reader</span>
            </p>
            <h1 class="font-display text-3xl text-ink truncate mt-1">{@resource.title}</h1>
          </div>

          <div class="flex items-center gap-3 shrink-0">
            <button
              :if={@is_admin?}
              type="button"
              phx-click="toggle_milestone_mode"
              aria-pressed={to_string(@milestone_mode)}
              class={[
                "font-mono text-[10px] uppercase tracking-widest px-3 py-1.5 rounded-sm border transition-colors cursor-pointer",
                if(@milestone_mode,
                  do: "bg-terracotta text-paper border-terracotta",
                  else:
                    "bg-paper text-ink-soft border-paper-2 hover:border-terracotta/40 hover:text-terracotta"
                )
              ]}
            >
              {if @milestone_mode, do: "Cancel placement", else: "Place milestone"}
            </button>

            <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft num">
              <span class="num">{@resource.page_count}</span> pages
            </p>
          </div>
        </header>

        <p
          :if={@milestone_mode}
          class="font-mono text-[10px] uppercase tracking-widest text-terracotta px-8 py-2 border-b border-paper-2 bg-terracotta/5"
        >
          Click anywhere on a page to drop a milestone.
        </p>

        <div id="pdf-canvas" class="flex-1 overflow-hidden">
          <.svelte
            name="PdfCanvasRenderer"
            props={
              %{
                file_url: @file_url,
                total_pages: @resource.page_count,
                annotations: svelte_annotations(@annotation_index),
                milestone_markers: svelte_milestones(@milestones),
                milestone_mode: @milestone_mode,
                rubber_stamps: svelte_stamps(@milestones),
                current_user_id: @current_user.id,
                total_readers: @total_readers,
                active_annotation_id: @active_annotation_id
              }
            }
            socket={@socket}
          />
        </div>
      </main>

      <aside class="w-[360px] shrink-0 bg-paper-2 border-l border-paper-2 flex flex-col">
        <header class="px-6 py-4 border-b border-paper-2/60 space-y-3">
          <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft">
            Margin · <span class="num">{filtered_count(@annotation_index, @filter_type)}</span>
            of <span class="num">{length(@annotation_index)}</span>
            notes
          </p>

          <nav aria-label="Filter by type" class="flex flex-wrap gap-1.5">
            <.filter_chip
              :for={chip <- filter_chips()}
              type={chip.type}
              label={chip.label}
              count={chip_count(@annotation_index, chip.type)}
              active?={@filter_type == chip.type}
            />
          </nav>
        </header>

        <div
          class="flex-1 overflow-y-auto px-6 py-6 space-y-2"
          id="margin-column"
          phx-hook="MarginColumn"
        >
          <.milestone_form_section
            :if={@milestone_form}
            form={@milestone_form}
            placement={@milestone_pending_placement}
          />

          <.milestone_panel
            :if={@milestones != [] and !@milestone_form}
            milestones={@milestones}
            total_readers={@total_readers}
            class="mb-4"
          />

          <.annotation_form_section
            :if={@annotation_form}
            form={@annotation_form}
            selection={@selection}
            type={@annotation_form_type}
          />

          <p
            :if={@annotation_index == [] and !@annotation_form}
            class="font-serif italic text-ink-soft"
          >
            Highlight a passage in the page to leave a note.
          </p>

          <p
            :if={@annotation_index != [] and filtered_count(@annotation_index, @filter_type) == 0}
            class="font-serif italic text-ink-soft"
          >
            No {filter_label(@filter_type)} on this book yet.
          </p>

          <div id="margin-notes" phx-update="stream" class="space-y-2">
            <.margin_note
              :for={{_dom_id, annotation} <- @streams.annotations}
              number={annotation.display_number}
              annotation={annotation}
              author_email={author_email(annotation)}
              active?={@active_annotation_id == annotation.id}
              reply_count={annotation.reply_count}
              expanded?={@expanded_thread_id == annotation.id}
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
      <p class="font-mono text-[10px] uppercase tracking-widest text-terracotta mb-2">
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
      <p class="font-mono text-[10px] uppercase tracking-widest text-terracotta mb-2">
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
          <span class="font-mono text-[10px] uppercase tracking-widest text-ink-soft">
            Private — only you
          </span>
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
     |> assign(:annotation_form_type, type)}
  end

  def handle_event("cancel_annotation", _params, socket) do
    {:noreply,
     socket
     |> assign(:selection, nil)
     |> assign(:annotation_form, nil)
     |> assign(:annotation_form_type, nil)}
  end

  def handle_event("toggle_milestone_mode", _params, socket) do
    if socket.assigns.is_admin? do
      next = !socket.assigns.milestone_mode

      {:noreply,
       socket
       |> assign(:milestone_mode, next)
       |> assign(:milestone_form, nil)
       |> assign(:milestone_pending_placement, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "milestone_placed",
        %{"page" => page, "position" => position},
        socket
      ) do
    actor = socket.assigns.current_user

    if socket.assigns.is_admin? do
      placement = %{page: page, position: position}

      form =
        Progress.MilestoneMarker
        |> AshPhoenix.Form.for_create(:create_milestone,
          actor: actor,
          params: %{
            "resource_id" => socket.assigns.resource.id,
            "page_number" => page,
            "position" => position,
            "label" => ""
          }
        )
        |> to_form()

      {:noreply,
       socket
       |> assign(:milestone_pending_placement, placement)
       |> assign(:milestone_form, form)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_milestone", _params, socket) do
    {:noreply,
     socket
     |> assign(:milestone_form, nil)
     |> assign(:milestone_pending_placement, nil)}
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

  def handle_event("save_milestone", %{"form" => params}, socket) do
    actor = socket.assigns.current_user
    placement = socket.assigns.milestone_pending_placement
    label = Map.get(params, "label", "")

    if is_nil(placement) do
      {:noreply, socket}
    else
      case Progress.create_milestone(
             socket.assigns.resource.id,
             placement.page,
             placement.position,
             label,
             actor: actor,
             load: [:created_by, :stamp_count, stamps: [:user]]
           ) do
        {:ok, _milestone} ->
          # Refresh from the canonical list so the new milestone shows up
          # in the right page-sorted slot, with stamps/stamp_count preloaded.
          {:noreply,
           socket
           |> refresh_milestones()
           |> assign(:milestone_form, nil)
           |> assign(:milestone_pending_placement, nil)
           |> assign(:milestone_mode, false)
           |> put_flash(:info, "Milestone placed.")}

        {:error, %AshPhoenix.Form{} = form} ->
          {:noreply, assign(socket, :milestone_form, form)}

        {:error, error} ->
          {:noreply,
           put_flash(socket, :error, "Couldn't place milestone: #{format_error(error)}")}
      end
    end
  end

  # Slice 15.1/15.2: Svelte's IntersectionObserver reports the page range
  # currently in (or near) the viewport. We expand by `@prefetch_buffer` on
  # each side, drop pages we've already loaded, and fetch the rest. New
  # annotations stream in; previously-loaded ones aren't re-queried.
  #
  # Slice 15.3 hot-path discipline: when the visible range hasn't changed
  # AND there's nothing new to load, return :noreply unchanged so we don't
  # bump assigns and trigger a wasted re-render on every scroll.
  def handle_event("pages_visible", %{"first" => first, "last" => last}, socket) do
    actor = socket.assigns.current_user
    total_pages = socket.assigns.resource.page_count

    visible = clamp_range({to_int(first), to_int(last)}, total_pages)
    prefetch = expand_range(visible, @prefetch_buffer, total_pages)

    new_pages =
      pages_in_range(prefetch, total_pages) -- MapSet.to_list(socket.assigns.loaded_pages)

    if visible == socket.assigns.visible_pages and new_pages == [] do
      {:noreply, socket}
    else
      socket =
        socket
        |> assign(:visible_pages, visible)
        |> load_pages(new_pages, actor)

      {:noreply, socket}
    end
  end

  def handle_event("set_filter", %{"type" => type}, socket) do
    filter_type = parse_filter_type(type)

    {:noreply,
     socket
     |> assign(:filter_type, filter_type)
     |> stream(
       :annotations,
       margin_stream_items(socket.assigns, filter_type),
       reset: true
     )}
  end

  # Margin → PDF: clicking a margin note focuses the annotation. The Svelte
  # component reacts to the new `active_annotation_id` prop by scrolling its
  # source page into view and pulsing the marker.
  #
  # Slice 15.3 hot-path discipline: skip work when the click landed on the
  # already-active note — re-streaming the same card is a wasted round-trip.
  def handle_event("select_annotation", %{"id" => id}, socket) do
    prev = socket.assigns.active_annotation_id

    if prev == id do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:active_annotation_id, id)
       |> refresh_annotation(prev)
       |> refresh_annotation(id)}
    end
  end

  # PDF → Margin: clicking a marker in the canvas focuses the annotation and
  # asks the margin column to scroll the matching card into view.
  def handle_event("annotation_clicked", %{"id" => id}, socket) do
    prev = socket.assigns.active_annotation_id

    if prev == id do
      # Same marker re-clicked — skip the assign churn but still nudge the
      # margin to scroll into view (the user may have scrolled it off-screen).
      {:noreply, push_event(socket, "scroll_to_margin_note", %{id: id})}
    else
      {:noreply,
       socket
       |> assign(:active_annotation_id, id)
       |> refresh_annotation(prev)
       |> refresh_annotation(id)
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

    {:noreply,
     socket
     |> refresh_annotation(prev)
     |> refresh_annotation(id)}
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
        {:noreply,
         socket
         |> insert_annotation(annotation)
         |> assign(:selection, nil)
         |> assign(:annotation_form, nil)
         |> assign(:annotation_form_type, nil)
         |> put_flash(:info, save_flash(type))}

      {:error, %AshPhoenix.Form{} = form} ->
        {:noreply, assign(socket, :annotation_form, form)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Couldn't save: #{format_error(error)}")}
    end
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

  # PubSub: a peer replied to an annotation on this resource. Always bump
  # the badge; only fetch the reply body if the matching thread is open.
  def handle_info(
        {:reply_created, %{id: id, annotation_id: annotation_id, resource_id: resource_id}},
        socket
      ) do
    if resource_id != socket.assigns.resource.id do
      {:noreply, socket}
    else
      socket = bump_reply_count(socket, annotation_id)

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

  # Slice 15.1: insert a freshly-created annotation into both the index
  # (drives Svelte markers + counts) and `annotations_by_id` (drives the
  # margin stream). Re-streams every note on the affected page so per-page
  # numbering stays correct: numbers shift when a new note lands at the
  # bottom of an already-rendered page.
  defp insert_annotation(socket, annotation) do
    if Map.has_key?(socket.assigns.annotations_by_id, annotation.id) do
      socket
    else
      stub = annotation_stub(annotation)
      index = socket.assigns.annotation_index ++ [stub]
      by_id = Map.put(socket.assigns.annotations_by_id, annotation.id, annotation)
      loaded_pages = MapSet.put(socket.assigns.loaded_pages, annotation.page_number)

      socket
      |> assign(:annotation_index, index)
      |> assign(:annotations_by_id, by_id)
      |> assign(:loaded_pages, loaded_pages)
      |> restream_page(annotation.page_number)
    end
  end

  defp bump_reply_count(socket, annotation_id) do
    case Map.get(socket.assigns.annotations_by_id, annotation_id) do
      nil ->
        socket

      annotation ->
        updated = %{annotation | reply_count: annotation.reply_count + 1}

        socket
        |> assign(
          :annotations_by_id,
          Map.put(socket.assigns.annotations_by_id, annotation_id, updated)
        )
        |> refresh_annotation(annotation_id)
    end
  end

  defp append_reply_if_open(socket, reply) do
    cond do
      socket.assigns.expanded_thread_id != reply.annotation_id ->
        socket

      Enum.any?(socket.assigns.thread_replies, &(&1.id == reply.id)) ->
        socket

      true ->
        socket
        |> assign(:thread_replies, socket.assigns.thread_replies ++ [reply])
        |> refresh_annotation(reply.annotation_id)
    end
  end

  # Streams don't auto-rerender items when outer assigns change. Anywhere a
  # margin-note's content depends on `active_annotation_id`, `expanded_thread_id`,
  # or `thread_replies`, push the affected card back through `stream_insert`.
  defp refresh_annotation(socket, nil), do: socket

  defp refresh_annotation(socket, id) do
    case Map.get(socket.assigns.annotations_by_id, id) do
      nil ->
        socket

      annotation ->
        if visible_under_filter?(annotation, socket.assigns.filter_type) do
          numbered = with_display_number(annotation, socket.assigns.annotation_index)
          stream_insert(socket, :annotations, numbered)
        else
          socket
        end
    end
  end

  defp fetch_reply(id, actor) do
    Ash.get(Annotations.AnnotationComment, id, actor: actor, load: [:user])
  end

  # Slice 15.1/15.2: hydrate full annotations for the given pages and merge
  # them into `annotations_by_id`. The stream gets every newly loaded page's
  # notes appended in `(page, inserted_at)` order so they slot in beside the
  # already-rendered ones without re-streaming the whole margin column.
  defp load_pages(socket, [], _actor), do: socket

  defp load_pages(socket, pages, actor) do
    fresh =
      Annotations.list_annotations_for_pages(
        socket.assigns.resource.id,
        pages,
        actor: actor
      )

    by_id =
      Enum.reduce(fresh, socket.assigns.annotations_by_id, fn annotation, acc ->
        Map.put(acc, annotation.id, annotation)
      end)

    loaded_pages =
      Enum.reduce(pages, socket.assigns.loaded_pages, fn page, acc ->
        MapSet.put(acc, page)
      end)

    socket
    |> assign(:annotations_by_id, by_id)
    |> assign(:loaded_pages, loaded_pages)
    |> stream_insert_many(
      filter_for_stream(fresh, socket.assigns.filter_type),
      socket.assigns.annotation_index
    )
  end

  defp stream_insert_many(socket, [], _index), do: socket

  defp stream_insert_many(socket, annotations, index) do
    Enum.reduce(annotations, socket, fn a, acc ->
      stream_insert(acc, :annotations, with_display_number(a, index))
    end)
  end

  defp init_stream(socket) do
    items = margin_stream_items(socket.assigns, socket.assigns.filter_type)
    stream(socket, :annotations, items, dom_id: &"margin-note-#{&1.id}")
  end

  # Re-stream every loaded annotation on `page` so per-page numbering stays
  # in lockstep with the index after an insert.
  defp restream_page(socket, page) do
    %{annotations_by_id: by_id, annotation_index: index, filter_type: filter} = socket.assigns

    by_id
    |> Map.values()
    |> Enum.filter(&(&1.page_number == page))
    |> Enum.filter(&visible_under_filter?(&1, filter))
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> Enum.reduce(socket, fn a, acc ->
      stream_insert(acc, :annotations, with_display_number(a, index))
    end)
  end

  defp margin_stream_items(assigns, filter_type) do
    assigns.annotations_by_id
    |> Map.values()
    |> Enum.filter(&visible_under_filter?(&1, filter_type))
    |> Enum.sort_by(&{&1.page_number, &1.inserted_at}, fn
      {p1, t1}, {p2, t2} ->
        cond do
          p1 < p2 -> true
          p1 > p2 -> false
          true -> DateTime.compare(t1, t2) != :gt
        end
    end)
    |> Enum.map(&with_display_number(&1, assigns.annotation_index))
  end

  defp filter_for_stream(annotations, filter_type) do
    annotations
    |> Enum.filter(&visible_under_filter?(&1, filter_type))
    |> Enum.sort_by(& &1.inserted_at, DateTime)
  end

  # Slice 15: per-page footnote numbering. Within a page, sort by
  # inserted_at and use 1-based position. The index is authoritative — even
  # for annotations whose page hasn't been hydrated yet, every annotation in
  # the index gets a stable number that the canvas marker can render.
  defp with_display_number(annotation, index) do
    Map.put(annotation, :display_number, page_display_number(annotation, index))
  end

  defp page_display_number(annotation, index) do
    index
    |> Enum.filter(&(&1.page_number == annotation.page_number))
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> Enum.find_index(&(&1.id == annotation.id))
    |> case do
      nil -> 1
      i -> i + 1
    end
  end

  # The index already carries `id`, `type`, `page_number`, `rect`,
  # `inserted_at`, `user_id`, `visibility` — the same shape we get from the
  # full record. After a local create we project back to that shape so the
  # marker map stays consistent without us tracking two schemas.
  defp annotation_stub(annotation) do
    %{
      id: annotation.id,
      type: annotation.type,
      page_number: annotation.page_number,
      rect: annotation.rect,
      inserted_at: annotation.inserted_at,
      user_id: annotation.user_id,
      visibility: annotation.visibility
    }
  end

  # ---- range arithmetic (Slice 15.1/15.2) ----

  defp pages_in_range({first, last}, total_pages) do
    first = max(1, first)
    last = min(last, total_pages)
    if last < first, do: [], else: Enum.to_list(first..last)
  end

  defp clamp_range({first, last}, total_pages) do
    first = max(1, first)
    last = max(first, min(last, total_pages))
    {first, last}
  end

  defp expand_range({first, last}, buffer, total_pages) do
    {max(1, first - buffer), min(total_pages, last + buffer)}
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

  # Slice 15.1: markers are built from the lightweight index — every
  # annotation visible to the actor, with per-page numbering. The body/text
  # never crosses the wire to Svelte.
  defp svelte_annotations(index) do
    index
    |> Enum.group_by(& &1.page_number)
    |> Enum.flat_map(fn {_page, page_annotations} ->
      page_annotations
      |> Enum.sort_by(& &1.inserted_at, DateTime)
      |> Enum.with_index(1)
      |> Enum.map(fn {a, idx} ->
        %{id: a.id, number: idx, page: a.page_number, rect: a.rect}
      end)
    end)
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

  defp parse_create_type("question"), do: :question
  defp parse_create_type("puzzle"), do: :puzzle
  defp parse_create_type(_), do: :comment

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
  defp form_label(_), do: "note"

  defp form_placeholder(:question), do: "Your question…"
  defp form_placeholder(:puzzle), do: "What's puzzling here?"
  defp form_placeholder(_), do: "Your note…"

  defp save_flash(:question), do: "Question saved."
  defp save_flash(:puzzle), do: "Puzzle saved."
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
end
