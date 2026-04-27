defmodule StudysyncWeb.PdfLive.Show do
  use StudysyncWeb, :live_view

  alias Studysync.Annotations
  alias Studysync.Annotations.PubSub, as: AnnotationsPubSub
  alias Studysync.Library

  def mount(%{"workspace_id" => workspace_id, "id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Library.get_resource(id, actor: actor, load: [:uploaded_by]) do
      {:ok, resource}
      when not is_nil(resource) and resource.workspace_id == workspace_id ->
        annotations =
          resource.id
          |> load_annotations(actor)
          |> assign_display_numbers()

        if connected?(socket), do: AnnotationsPubSub.subscribe(resource.id)

        {:ok,
         socket
         |> assign(:resource, resource)
         |> assign(:workspace_id, workspace_id)
         |> assign(:file_url, ~p"/resources/#{resource.id}/file")
         |> assign(:page_title, resource.title)
         |> assign(:annotations, annotations)
         |> assign(:annotation_counter, length(annotations))
         |> assign(:selection, nil)
         |> assign(:annotation_form, nil)
         |> assign(:annotation_form_type, nil)
         |> assign(:active_annotation_id, nil)
         |> assign(:expanded_thread_id, nil)
         |> assign(:thread_replies, [])
         |> assign(:reply_form, nil)
         |> assign(:filter_type, :all)
         |> stream(
           :annotations,
           filtered(annotations, :all),
           dom_id: &"margin-note-#{&1.id}"
         )}

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
        <header class="flex items-baseline justify-between border-b border-paper-2 px-8 py-4">
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
          <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft num shrink-0">
            <span class="num">{@resource.page_count}</span> pages
          </p>
        </header>

        <div id="pdf-canvas" class="flex-1 overflow-hidden">
          <.svelte
            name="PdfCanvasRenderer"
            props={
              %{
                file_url: @file_url,
                total_pages: @resource.page_count,
                annotations: svelte_annotations(@annotations),
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
            Margin · <span class="num">{filtered_count(@annotations, @filter_type)}</span>
            of <span class="num">{length(@annotations)}</span>
            notes
          </p>

          <nav aria-label="Filter by type" class="flex flex-wrap gap-1.5">
            <.filter_chip
              :for={chip <- filter_chips()}
              type={chip.type}
              label={chip.label}
              count={chip_count(@annotations, chip.type)}
              active?={@filter_type == chip.type}
            />
          </nav>
        </header>

        <div
          class="flex-1 overflow-y-auto px-6 py-6 space-y-2"
          id="margin-column"
          phx-hook="MarginColumn"
        >
          <.annotation_form_section
            :if={@annotation_form}
            form={@annotation_form}
            selection={@selection}
            type={@annotation_form_type}
          />

          <p
            :if={@annotations == [] and !@annotation_form}
            class="font-serif italic text-ink-soft"
          >
            Highlight a passage in the page to leave a note.
          </p>

          <p
            :if={@annotations != [] and filtered_count(@annotations, @filter_type) == 0}
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
          "body" => ""
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

  def handle_event("set_filter", %{"type" => type}, socket) do
    filter_type = parse_filter_type(type)

    {:noreply,
     socket
     |> assign(:filter_type, filter_type)
     |> stream(
       :annotations,
       filtered(socket.assigns.annotations, filter_type),
       reset: true
     )}
  end

  # Margin → PDF: clicking a margin note focuses the annotation. The Svelte
  # component reacts to the new `active_annotation_id` prop by scrolling its
  # source page into view and pulsing the marker.
  def handle_event("select_annotation", %{"id" => id}, socket) do
    prev = socket.assigns.active_annotation_id

    {:noreply,
     socket
     |> assign(:active_annotation_id, id)
     |> refresh_annotation(prev)
     |> refresh_annotation(id)}
  end

  # PDF → Margin: clicking a marker in the canvas focuses the annotation and
  # asks the margin column to scroll the matching card into view.
  def handle_event("annotation_clicked", %{"id" => id}, socket) do
    prev = socket.assigns.active_annotation_id

    {:noreply,
     socket
     |> assign(:active_annotation_id, id)
     |> refresh_annotation(prev)
     |> refresh_annotation(id)
     |> push_event("scroll_to_margin_note", %{id: id})}
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

    result =
      apply(Annotations, create_fun_for(type), [
        socket.assigns.resource.id,
        selection.page,
        selection.rect,
        selection.text,
        body,
        [actor: actor, load: [:user, :reply_count]]
      ])

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

  defp insert_annotation(socket, annotation) do
    if Enum.any?(socket.assigns.annotations, &(&1.id == annotation.id)) do
      socket
    else
      next_number = socket.assigns.annotation_counter + 1
      numbered = Map.put(annotation, :display_number, next_number)

      socket =
        socket
        |> assign(:annotation_counter, next_number)
        |> assign(:annotations, socket.assigns.annotations ++ [numbered])

      if visible_under_filter?(numbered, socket.assigns.filter_type) do
        stream_insert(socket, :annotations, numbered)
      else
        socket
      end
    end
  end

  defp bump_reply_count(socket, annotation_id) do
    case Enum.find(socket.assigns.annotations, &(&1.id == annotation_id)) do
      nil ->
        socket

      annotation ->
        updated = %{annotation | reply_count: annotation.reply_count + 1}

        annotations =
          Enum.map(socket.assigns.annotations, fn a ->
            if a.id == annotation_id, do: updated, else: a
          end)

        socket = assign(socket, :annotations, annotations)

        if visible_under_filter?(updated, socket.assigns.filter_type) do
          stream_insert(socket, :annotations, updated)
        else
          socket
        end
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
    case Enum.find(socket.assigns.annotations, &(&1.id == id)) do
      nil ->
        socket

      annotation ->
        if visible_under_filter?(annotation, socket.assigns.filter_type) do
          stream_insert(socket, :annotations, annotation)
        else
          socket
        end
    end
  end

  defp fetch_reply(id, actor) do
    Ash.get(Annotations.AnnotationComment, id, actor: actor, load: [:user])
  end

  defp load_annotations(resource_id, actor) do
    Annotations.list_annotations!(
      actor: actor,
      query: [filter: [resource_id: resource_id], sort: [inserted_at: :asc]],
      load: [:user, :reply_count]
    )
  end

  defp assign_display_numbers(annotations) do
    annotations
    |> Enum.with_index(1)
    |> Enum.map(fn {a, idx} -> Map.put(a, :display_number, idx) end)
  end

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

  defp svelte_annotations(annotations) do
    Enum.map(annotations, fn a ->
      %{
        id: a.id,
        number: a.display_number,
        page: a.page_number,
        rect: a.rect
      }
    end)
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

  defp filtered(annotations, :all), do: annotations

  defp filtered(annotations, type) when type in [:comment, :question, :puzzle] do
    Enum.filter(annotations, &(&1.type == type))
  end

  defp filtered_count(annotations, type) do
    annotations |> filtered(type) |> length()
  end

  defp chip_count(annotations, :all), do: length(annotations)
  defp chip_count(annotations, type), do: filtered_count(annotations, type)

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
end
