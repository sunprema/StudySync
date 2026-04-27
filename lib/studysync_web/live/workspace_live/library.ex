defmodule StudysyncWeb.WorkspaceLive.Library do
  use StudysyncWeb, :live_view

  require Ash.Query

  alias Studysync.Activity
  alias Studysync.Activity.PubSub, as: ActivityPubSub
  alias Studysync.Annotations.Annotation
  alias Studysync.Library
  alias Studysync.Library.Resource
  alias Studysync.Progress.MilestoneMarker
  alias Studysync.Workspaces
  alias Studysync.Workspaces.Membership

  @max_file_size 50_000_000
  @activity_limit 25

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Workspaces.get_workspace(id, actor: actor) do
      {:ok, workspace} when not is_nil(workspace) ->
        resources =
          Library.list_resources!(
            actor: actor,
            query: [filter: [workspace_id: workspace.id], sort: [inserted_at: :desc]],
            load: [:uploaded_by, :avg_progress_percent]
          )

        members = active_members(workspace.id)
        progress_matrix = member_progress_matrix(resources, members)
        milestones_by_resource = milestones_by_resource(resources)

        events = Activity.list_for_workspace(workspace.id, actor: actor, limit: @activity_limit)

        if connected?(socket), do: ActivityPubSub.subscribe(workspace.id)

        socket =
          socket
          |> assign(:workspace, workspace)
          |> assign(:page_title, workspace.name <> " — Library")
          |> assign(:title, "")
          |> assign(:upload_error, nil)
          |> assign(:members, members)
          |> assign(:progress_matrix, progress_matrix)
          |> assign(:milestones_by_resource, milestones_by_resource)
          |> assign(:activity_event_ids, MapSet.new(Enum.map(events, & &1.id)))
          |> stream(:resources, resources)
          |> stream(:activity_events, events, dom_id: &"activity-#{&1.id}")
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

  def terminate(_reason, socket) do
    if Map.get(socket.assigns, :workspace) do
      ActivityPubSub.unsubscribe(socket.assigns.workspace.id)
    end

    :ok
  end

  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen w-full bg-paper text-ink">
      <main class="flex-1 min-w-0 px-8 py-12">
        <div class="mx-auto max-w-4xl">
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
            <h2 class="font-mono text-xs uppercase tracking-widest text-ink-soft mb-6">
              Books
            </h2>

            <div id="resources" phx-update="stream" class="space-y-12">
              <p
                id="resources-empty"
                class="hidden only:block font-serif italic text-ink-soft py-4"
              >
                No PDFs yet. Add the first one above.
              </p>

              <article
                :for={{dom_id, resource} <- @streams.resources}
                id={dom_id}
                class="border-b border-paper-2 pb-12 last:border-b-0"
              >
                <header class="flex items-baseline justify-between gap-6 mb-4">
                  <div class="min-w-0">
                    <.link
                      navigate={~p"/workspaces/#{@workspace.id}/library/#{resource.id}"}
                      class="hover:text-terracotta transition-colors"
                    >
                      <h3 class="font-display text-4xl text-ink truncate">{resource.title}</h3>
                    </.link>
                    <p class="font-mono text-xs uppercase tracking-widest text-ink-soft mt-2">
                      <span class="num">{resource.page_count}</span>
                      pages · <span class="num">{length(@members)}</span>
                      {if length(@members) == 1, do: "reader", else: "readers"} · started {format_date(
                        resource.inserted_at
                      )}<span :if={uploader_email(resource)}>
                        · {uploader_email(resource)}</span>
                    </p>
                  </div>
                  <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft shrink-0">
                    Group avg
                    <span class="font-display text-3xl text-terracotta num ml-1">
                      {resource.avg_progress_percent || 0}%
                    </span>
                  </p>
                </header>

                <div class="px-6 pt-5 pb-7 bg-paper-2/40 rounded">
                  <.progress_timeline
                    members={members_for(@progress_matrix, resource.id)}
                    current_user_id={@current_user.id}
                    milestones={milestones_for(@milestones_by_resource, resource.id)}
                    total_pages={resource.page_count}
                    avg_progress_percent={resource.avg_progress_percent || 0}
                    total_time_spent_seconds={total_time_spent(@progress_matrix, resource.id)}
                  />
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-3 mt-6">
                  <.reader_card
                    :for={member <- members_for(@progress_matrix, resource.id)}
                    member={member}
                    is_self={member.user_id == @current_user.id}
                  />
                </div>

                <div class="mt-6">
                  <.link
                    navigate={~p"/workspaces/#{@workspace.id}/library/#{resource.id}"}
                    class="font-mono text-xs uppercase tracking-widest text-terracotta hover:underline"
                  >
                    Open book →
                  </.link>
                </div>
              </article>
            </div>
          </section>
        </div>
      </main>

      <aside class="hidden lg:flex w-[340px] shrink-0 bg-paper-2 border-l border-paper-2/60 flex-col">
        <header class="px-6 py-5 border-b border-paper-2/60 flex items-baseline justify-between">
          <h2 class="font-display italic text-3xl text-ink">Recent</h2>
          <span class="font-mono text-[10px] uppercase tracking-widest text-terracotta border border-terracotta/40 px-2 py-px rounded-sm">
            Live
          </span>
        </header>

        <div class="flex-1 overflow-y-auto px-6 py-2">
          <div id="activity-feed" phx-update="stream">
            <p
              id="activity-feed-empty"
              class="hidden only:block font-serif italic text-ink-soft py-4"
            >
              Nothing yet. Highlight or reply on a page to fill the rail.
            </p>

            <div :for={{dom_id, event} <- @streams.activity_events} id={dom_id}>
              <.activity_item event={event} workspace_id={@workspace.id} />
            </div>
          </div>
        </div>
      </aside>
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
            # Newly uploaded resource has no annotations yet, so its row in the
            # matrix is just every member at zero. Building it lazily here
            # keeps the matrix complete without a re-fetch.
            empty_row = empty_matrix_row(socket.assigns.members)
            matrix = Map.put(socket.assigns.progress_matrix, resource.id, empty_row)

            milestones =
              Map.put(socket.assigns.milestones_by_resource, resource.id, [])

            {:noreply,
             socket
             |> assign(:title, "")
             |> assign(:upload_error, nil)
             |> assign(:progress_matrix, matrix)
             |> assign(:milestones_by_resource, milestones)
             |> stream_insert(:resources, resource, at: 0)
             |> put_flash(:info, "PDF uploaded.")}

          [{:error, error}] ->
            {:noreply, assign(socket, :upload_error, format_error(error))}

          [] ->
            {:noreply, assign(socket, :upload_error, "Upload failed.")}
        end
    end
  end

  # Activity rail (Slice 8): a peer just created an annotation in a resource
  # somewhere in this workspace. Refetch as our actor so private items don't
  # leak past their author.
  #
  # Also recompute the progress matrix row for the annotation's resource and
  # `stream_insert` the resource so the open dashboard's progress timeline,
  # group-avg badge, and reader cards reflect the new annotation in real
  # time. Without this the matrix stays at its mount-time snapshot and shows
  # stale 0% / 0s for users whose annotations arrive while the page is open.
  def handle_info(
        {:activity_annotation_created, %{annotation_id: annotation_id, workspace_id: ws_id}},
        socket
      ) do
    if ws_id == socket.assigns.workspace.id do
      socket = refresh_progress_for_annotation(socket, annotation_id)

      handle_activity(socket, fn ->
        Activity.event_from_annotation(annotation_id, actor: socket.assigns.current_user)
      end)
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:activity_reply_created, %{reply_id: reply_id, workspace_id: ws_id}},
        socket
      ) do
    if ws_id == socket.assigns.workspace.id do
      handle_activity(socket, fn ->
        Activity.event_from_reply(reply_id, actor: socket.assigns.current_user)
      end)
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:activity_stamp_applied, %{stamp_id: stamp_id, workspace_id: ws_id}},
        socket
      ) do
    if ws_id == socket.assigns.workspace.id do
      handle_activity(socket, fn ->
        Activity.event_from_stamp(stamp_id, actor: socket.assigns.current_user)
      end)
    else
      {:noreply, socket}
    end
  end

  defp handle_activity(socket, fetch_fun) do
    case fetch_fun.() do
      {:ok, event} ->
        if MapSet.member?(socket.assigns.activity_event_ids, event.id) do
          {:noreply, socket}
        else
          {:noreply,
           socket
           |> assign(
             :activity_event_ids,
             MapSet.put(socket.assigns.activity_event_ids, event.id)
           )
           |> stream_insert(:activity_events, event, at: 0, limit: @activity_limit)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp uploader_email(%{uploaded_by: %{email: email}}) when not is_nil(email),
    do: to_string(email)

  defp uploader_email(_), do: nil

  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %d, %Y")

  # Active members of the workspace, with their User loaded. Read with
  # `authorize?: false` because the dashboard's row-level visibility is
  # already gated on the actor's workspace membership at the page level —
  # this just shapes the roster.
  defp active_members(workspace_id) do
    Membership
    |> Ash.Query.filter(workspace_id == ^workspace_id and status == :active)
    |> Ash.Query.load(:user)
    |> Ash.read!(authorize?: false)
    |> Enum.map(fn m ->
      %{
        user_id: m.user_id,
        email: m.user && to_string(m.user.email)
      }
    end)
    |> Enum.reject(&is_nil(&1.user_id))
  end

  # Build a `%{resource_id => [%{user_id, email, progress_percent,
  # time_spent_seconds}]}` matrix in one annotations query. The Ash
  # calculations on Resource are the canonical per-pair definitions; this
  # helper duplicates their math so the dashboard can render the whole
  # cross-product in a single SQL hop instead of N×M loads.
  defp member_progress_matrix([], _members), do: %{}
  defp member_progress_matrix(_resources, []), do: %{}

  defp member_progress_matrix(resources, members) do
    resource_ids = Enum.map(resources, & &1.id)
    member_ids = Enum.map(members, & &1.user_id)
    page_counts = Map.new(resources, &{&1.id, &1.page_count})

    grouped =
      Annotation
      |> Ash.Query.filter(resource_id in ^resource_ids and user_id in ^member_ids)
      |> Ash.Query.select([:resource_id, :user_id, :page_number, :inserted_at])
      |> Ash.read!(authorize?: false)
      |> Enum.group_by(&{&1.resource_id, &1.user_id})

    Map.new(resources, fn r ->
      pc = Map.fetch!(page_counts, r.id)

      row =
        Enum.map(members, fn m ->
          anns = Map.get(grouped, {r.id, m.user_id}, [])
          progress_percent = compute_progress_percent(anns, pc)
          time_spent_seconds = compute_time_spent(anns)

          %{
            user_id: m.user_id,
            email: m.email,
            progress_percent: progress_percent,
            time_spent_seconds: time_spent_seconds
          }
        end)

      {r.id, row}
    end)
  end

  defp compute_progress_percent([], _pc), do: 0
  defp compute_progress_percent(_anns, pc) when pc <= 0, do: 0

  defp compute_progress_percent(anns, pc) do
    max = anns |> Enum.map(& &1.page_number) |> Enum.max(fn -> 0 end)
    if max <= 0, do: 0, else: min(100, trunc(max * 100 / pc))
  end

  defp compute_time_spent([]), do: 0
  defp compute_time_spent([_]), do: 0

  defp compute_time_spent(anns) do
    timestamps = Enum.map(anns, & &1.inserted_at)
    DateTime.diff(Enum.max(timestamps, DateTime), Enum.min(timestamps, DateTime), :second)
  end

  # Recompute the matrix row for a single resource and re-stream the
  # resource so its article re-renders. Triggered from a peer's
  # `:activity_annotation_created` broadcast — we only know the annotation
  # id, so we look up its resource_id and rebuild that row only.
  #
  # `authorize?: false` on the annotation lookup is intentional: progress
  # math reads page_number metadata only, mirroring the existing
  # `member_progress_matrix` (and the per-user `ProgressPercent` calc, see
  # its Slice 14 audit note). The resource itself is reloaded with the
  # actor so authorization on the resource record stays honest.
  defp refresh_progress_for_annotation(socket, annotation_id) do
    case Ash.get(Annotation, annotation_id, authorize?: false) do
      {:ok, %{resource_id: resource_id}} when not is_nil(resource_id) ->
        refresh_resource_progress(socket, resource_id)

      _ ->
        socket
    end
  end

  defp refresh_resource_progress(socket, resource_id) do
    actor = socket.assigns.current_user

    case Ash.get(Resource, resource_id,
           actor: actor,
           load: [:uploaded_by, :avg_progress_percent]
         ) do
      {:ok, resource} ->
        members = socket.assigns.members
        row = compute_resource_row(resource, members)
        matrix = Map.put(socket.assigns.progress_matrix, resource.id, row)

        socket
        |> assign(:progress_matrix, matrix)
        |> stream_insert(:resources, resource)

      _ ->
        socket
    end
  end

  defp compute_resource_row(resource, members) do
    member_ids = Enum.map(members, & &1.user_id)
    pc = resource.page_count || 0

    grouped =
      Annotation
      |> Ash.Query.filter(resource_id == ^resource.id and user_id in ^member_ids)
      |> Ash.Query.select([:user_id, :page_number, :inserted_at])
      |> Ash.read!(authorize?: false)
      |> Enum.group_by(& &1.user_id)

    Enum.map(members, fn m ->
      anns = Map.get(grouped, m.user_id, [])

      %{
        user_id: m.user_id,
        email: m.email,
        progress_percent: compute_progress_percent(anns, pc),
        time_spent_seconds: compute_time_spent(anns)
      }
    end)
  end

  defp empty_matrix_row(members) do
    Enum.map(members, fn m ->
      %{
        user_id: m.user_id,
        email: m.email,
        progress_percent: 0,
        time_spent_seconds: 0
      }
    end)
  end

  defp members_for(matrix, resource_id) do
    Map.get(matrix, resource_id, [])
  end

  # Single milestone fetch grouped by resource_id. Read with `authorize?:
  # false` for the same reason the membership roster is — page-level
  # workspace membership has already been authorised, and milestones are
  # workspace-public guideposts (see MilestoneMarker policy).
  defp milestones_by_resource([]), do: %{}

  defp milestones_by_resource(resources) do
    resource_ids = Enum.map(resources, & &1.id)

    MilestoneMarker
    |> Ash.Query.filter(resource_id in ^resource_ids)
    |> Ash.Query.sort(page_number: :asc)
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.resource_id)
  end

  defp milestones_for(by_resource, resource_id) do
    Map.get(by_resource, resource_id, [])
  end

  defp total_time_spent(matrix, resource_id) do
    matrix
    |> Map.get(resource_id, [])
    |> Enum.map(&(Map.get(&1, :time_spent_seconds) || 0))
    |> Enum.sum()
  end

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
