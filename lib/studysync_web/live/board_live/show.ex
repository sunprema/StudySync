defmodule StudysyncWeb.BoardLive.Show do
  use StudysyncWeb, :live_view

  alias Studysync.Board
  alias Studysync.Board.PubSub, as: BoardPubSub
  alias Studysync.Library
  alias Studysync.Presence
  alias Studysync.Workspaces

  require Ash.Query

  @presence_topic_prefix "board:"

  def mount(%{"workspace_id" => workspace_id, "id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Library.get_resource(id, actor: actor) do
      {:ok, resource}
      when not is_nil(resource) and resource.workspace_id == workspace_id ->
        nodes = load_nodes(resource.id, actor)
        edges = load_edges(resource.id, actor)
        is_admin? = Workspaces.actor_admin?(workspace_id, actor)

        if connected?(socket) do
          BoardPubSub.subscribe(resource.id)

          {:ok, _} =
            Presence.track(
              self(),
              @presence_topic_prefix <> resource.id,
              actor.id,
              %{email: to_string(actor.email)}
            )
        end

        here_now = board_here_now(resource.id)

        socket =
          socket
          |> assign(:resource, resource)
          |> assign(:workspace_id, workspace_id)
          |> assign(:page_title, resource.title <> " · Board")
          |> assign(:nodes, nodes)
          |> assign(:edges, edges)
          |> assign(:is_admin?, is_admin?)
          |> assign(:here_now, here_now)

        {:ok, socket}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Resource not found.")
         |> push_navigate(to: ~p"/workspaces/#{workspace_id}/library")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-paper text-ink overflow-hidden">
      <header class="topbar shrink-0">
        <div class="flex-1 min-w-0">
          <p class="section-label">
            <.link
              navigate={~p"/workspaces/#{@workspace_id}/library/#{@resource.id}"}
              class="hover:text-terracotta transition-colors"
            >
              ← Reader
            </.link>
            <span class="text-ink-soft/40 mx-1">·</span>
            Board
          </p>
          <h1 class="font-display text-2xl text-ink truncate leading-tight">{@resource.title}</h1>
        </div>

        <div class="flex items-center gap-4 shrink-0">
          <span class="mono-tag">HERE NOW · {@here_now}</span>
          <StudysyncWeb.Layouts.user_menu current_user={@current_user} />
        </div>
      </header>

      <div class="flex-1 overflow-hidden">
        <.svelte
          name="ConceptMapBoard"
          props={
            %{
              nodes: board_nodes(@nodes),
              edges: board_edges(@edges),
              current_user_id: @current_user.id
            }
          }
          socket={@socket}
        />
      </div>
    </div>
    """
  end

  # --- Svelte events ---

  def handle_event(
        "node_created",
        %{"label" => label, "position_x" => px, "position_y" => py},
        socket
      ) do
    actor = socket.assigns.current_user

    case Board.create_node(socket.assigns.resource.id, label, px, py, actor: actor) do
      {:ok, _node} ->
        {:noreply, reload_board(socket)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "node_moved",
        %{"id" => id, "position_x" => px, "position_y" => py},
        socket
      ) do
    actor = socket.assigns.current_user

    case Board.get_node(id, actor: actor) do
      {:ok, node} ->
        Board.move_node(node, px, py, actor: actor)
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("node_deleted", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    case Board.get_node(id, actor: actor) do
      {:ok, node} ->
        :ok = Board.delete_node(node, actor: actor)
        {:noreply, reload_board(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "edge_created",
        %{"source_id" => source_id, "target_id" => target_id},
        socket
      ) do
    actor = socket.assigns.current_user

    case Board.create_edge(socket.assigns.resource.id, source_id, target_id, actor: actor) do
      {:ok, _edge} ->
        {:noreply, reload_board(socket)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("edge_deleted", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    case Board.get_edge(id, actor: actor) do
      {:ok, edge} ->
        :ok = Board.delete_edge(edge, actor: actor)
        {:noreply, reload_board(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  # --- PubSub ---

  def handle_info({event, %{resource_id: resource_id}}, socket)
      when event in [:node_created, :node_moved, :node_deleted, :edge_created, :edge_deleted] and
             resource_id == socket.assigns.resource.id do
    {:noreply, reload_board(socket)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{event: "presence_diff", topic: topic},
        socket
      ) do
    if topic == @presence_topic_prefix <> socket.assigns.resource.id do
      {:noreply, assign(socket, :here_now, board_here_now(socket.assigns.resource.id))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp reload_board(socket) do
    actor = socket.assigns.current_user
    resource_id = socket.assigns.resource.id

    socket
    |> assign(:nodes, load_nodes(resource_id, actor))
    |> assign(:edges, load_edges(resource_id, actor))
  end

  defp load_nodes(resource_id, actor) do
    Studysync.Board.Node
    |> Ash.Query.filter(resource_id == ^resource_id)
    |> Ash.read!(actor: actor)
  end

  defp load_edges(resource_id, actor) do
    Studysync.Board.Edge
    |> Ash.Query.filter(resource_id == ^resource_id)
    |> Ash.read!(actor: actor)
  end

  defp board_here_now(resource_id) do
    (@presence_topic_prefix <> resource_id)
    |> Presence.list()
    |> map_size()
  end

  defp board_nodes(nodes) do
    Enum.map(nodes, fn n ->
      %{
        id: n.id,
        label: n.label,
        position_x: n.position_x,
        position_y: n.position_y,
        color: n.color || "default",
        user_id: n.user_id
      }
    end)
  end

  defp board_edges(edges) do
    Enum.map(edges, fn e ->
      %{
        id: e.id,
        source_id: e.source_id,
        target_id: e.target_id,
        label: e.label
      }
    end)
  end
end
