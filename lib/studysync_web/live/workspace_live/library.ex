defmodule StudysyncWeb.WorkspaceLive.Library do
  use StudysyncWeb, :live_view

  alias Studysync.Library
  alias Studysync.Workspaces

  @max_file_size 50_000_000

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Workspaces.get_workspace(id, actor: actor) do
      {:ok, workspace} when not is_nil(workspace) ->
        resources =
          Library.list_resources!(
            actor: actor,
            query: [filter: [workspace_id: workspace.id], sort: [inserted_at: :desc]],
            load: [:uploaded_by]
          )

        socket =
          socket
          |> assign(:workspace, workspace)
          |> assign(:page_title, workspace.name <> " — Library")
          |> assign(:title, "")
          |> assign(:upload_error, nil)
          |> stream(:resources, resources)
          |> allow_upload(:pdf,
            accept: ~w(.pdf application/pdf),
            max_entries: 1,
            max_file_size: @max_file_size
          )

        {:ok, socket}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Workspace not found.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-8 py-12">
      <header class="border-b border-paper-2 pb-6 mb-10">
        <p class="font-mono text-xs uppercase tracking-widest text-ink-soft">
          <.link navigate={~p"/workspaces/#{@workspace.id}"} class="hover:text-terracotta">
            {@workspace.name}
          </.link>
          <span> · Library</span>
        </p>
        <h1 class="font-display text-5xl text-ink mt-1">Library</h1>
      </header>

      <section class="mb-12">
        <h2 class="font-mono text-xs uppercase tracking-widest text-ink-soft mb-2">
          Add a PDF
        </h2>

        <form
          id="upload-form"
          phx-change="validate"
          phx-submit="upload"
          class="space-y-4 border border-paper-2 bg-paper-2/40 p-5 rounded"
        >
          <div>
            <label
              for="resource-title"
              class="font-mono text-xs uppercase tracking-widest text-ink-soft"
            >
              Title
            </label>
            <input
              id="resource-title"
              name="title"
              type="text"
              value={@title}
              placeholder="Invisible Cities"
              class="w-full input mt-1"
              required
            />
          </div>

          <div>
            <label class="font-mono text-xs uppercase tracking-widest text-ink-soft">
              PDF file
            </label>
            <.live_file_input upload={@uploads.pdf} class="block mt-1" />
            <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft mt-1">
              Max 50 MB
            </p>
          </div>

          <div :for={entry <- @uploads.pdf.entries} class="flex items-center gap-3">
            <span class="font-serif text-sm text-ink truncate">{entry.client_name}</span>
            <progress
              value={entry.progress}
              max="100"
              class="progress progress-primary flex-1"
            >
              {entry.progress}%
            </progress>
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              class="btn btn-ghost btn-xs"
            >
              cancel
            </button>
          </div>

          <div :for={err <- upload_errors(@uploads.pdf)} class="text-error font-mono text-xs">
            {error_to_string(err)}
          </div>

          <p :if={@upload_error} class="text-error font-mono text-xs">{@upload_error}</p>

          <div class="flex gap-3">
            <button type="submit" class="btn btn-primary">Upload</button>
            <.link navigate={~p"/workspaces/#{@workspace.id}"} class="btn btn-ghost">
              Back
            </.link>
          </div>
        </form>
      </section>

      <section>
        <h2 class="font-mono text-xs uppercase tracking-widest text-ink-soft mb-4">
          Resources
        </h2>

        <div id="resources" phx-update="stream">
          <p
            id="resources-empty"
            class="hidden only:block font-serif italic text-ink-soft py-4"
          >
            No PDFs yet. Add the first one above.
          </p>

          <div :for={{dom_id, resource} <- @streams.resources} id={dom_id}>
            <.resource_card
              resource={resource}
              uploader_email={uploader_email(resource)}
            />
          </div>
        </div>
      </section>
    </div>
    """
  end

  def handle_event("validate", %{"title" => title}, socket) do
    {:noreply, assign(socket, :title, title)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :pdf, ref)}
  end

  def handle_event("upload", %{"title" => title}, socket) do
    actor = socket.assigns.current_user
    workspace = socket.assigns.workspace

    case socket.assigns.uploads.pdf.entries do
      [] ->
        {:noreply, assign(socket, :upload_error, "Pick a PDF file first.")}

      _ ->
        results =
          consume_uploaded_entries(socket, :pdf, fn %{path: path}, _entry ->
            case Library.upload_resource(
                   workspace.id,
                   title,
                   %{path: path, filename: Path.basename(path)},
                   actor: actor,
                   load: [:uploaded_by]
                 ) do
              {:ok, resource} -> {:ok, {:ok, resource}}
              {:error, error} -> {:ok, {:error, error}}
            end
          end)

        case results do
          [{:ok, resource}] ->
            {:noreply,
             socket
             |> assign(:title, "")
             |> assign(:upload_error, nil)
             |> stream_insert(:resources, resource, at: 0)
             |> put_flash(:info, "PDF uploaded.")}

          [{:error, error}] ->
            {:noreply, assign(socket, :upload_error, format_error(error))}

          [] ->
            {:noreply, assign(socket, :upload_error, "Upload failed.")}
        end
    end
  end

  defp uploader_email(%{uploaded_by: %{email: email}}) when not is_nil(email),
    do: to_string(email)

  defp uploader_email(_), do: nil

  defp error_to_string(:too_large), do: "File is too large."
  defp error_to_string(:not_accepted), do: "Only PDF files are accepted."
  defp error_to_string(:too_many_files), do: "Only one file at a time."
  defp error_to_string(other), do: to_string(other)

  defp format_error(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.map_join(", ", fn
      %{message: msg} -> msg
      other -> inspect(other)
    end)
  end

  defp format_error(%Ash.Error.Forbidden{}),
    do: "You are not allowed to upload to this workspace."

  defp format_error(other), do: inspect(other)
end
