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
         |> assign(:active_annotation_id, nil)
         |> assign(:expanded_thread_id, nil)
         |> assign(:thread_replies, [])
         |> assign(:reply_form, nil)
         |> stream(:annotations, annotations, dom_id: &"margin-note-#{&1.id}")}

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
        <header class="px-6 py-4 border-b border-paper-2/60">
          <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft">
            Margin · <span class="num">{length(@annotations)}</span> notes
          </p>
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
          />

          <p
            :if={@annotations == [] and !@annotation_form}
            class="font-serif italic text-ink-soft"
          >
            Highlight a passage in the page to leave a note.
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

  defp annotation_form_section(assigns) do
    ~H"""
    <section class="border-l-2 border-terracotta pl-4 py-3 mb-4 bg-paper">
      <p class="font-mono text-[10px] uppercase tracking-widest text-terracotta mb-2">
        New note · page <span class="num">{@selection.page}</span>
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
          placeholder="Your note…"
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

  def handle_event("text_selected", %{"text" => text, "page" => page, "rect" => rect}, socket) do
    selection = %{
      text: text,
      page: page,
      rect: rect
    }

    form =
      Annotations.Annotation
      |> AshPhoenix.Form.for_create(:create_comment,
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
     |> assign(:annotation_form, form)}
  end

  def handle_event("cancel_annotation", _params, socket) do
    {:noreply, socket |> assign(:selection, nil) |> assign(:annotation_form, nil)}
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

    body = Map.get(params, "body", "")

    case Annotations.create_comment(
           socket.assigns.resource.id,
           selection.page,
           selection.rect,
           selection.text,
           body,
           actor: actor,
           load: [:user, :reply_count]
         ) do
      {:ok, annotation} ->
        {:noreply,
         socket
         |> insert_annotation(annotation)
         |> assign(:selection, nil)
         |> assign(:annotation_form, nil)
         |> put_flash(:info, "Note saved.")}

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

      socket
      |> assign(:annotation_counter, next_number)
      |> assign(:annotations, socket.assigns.annotations ++ [numbered])
      |> stream_insert(:annotations, numbered)
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

        socket
        |> assign(:annotations, annotations)
        |> stream_insert(:annotations, updated)
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
      nil -> socket
      annotation -> stream_insert(socket, :annotations, annotation)
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
