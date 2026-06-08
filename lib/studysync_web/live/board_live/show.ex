defmodule StudysyncWeb.BoardLive.Show do
  use StudysyncWeb, :live_view

  alias Studysync.Annotations
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
        annotations = Annotations.list_annotations_for_resource(resource.id, actor: actor)
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
          |> assign(:file_url, ~p"/resources/#{resource.id}/file")
          |> assign(:page_title, resource.title <> " · Board")
          |> assign(:nodes, nodes)
          |> assign(:edges, edges)
          |> assign(:annotations, annotations)
          |> assign(:is_admin?, is_admin?)
          |> assign(:here_now, here_now)
          |> assign(:reactions, load_reactions(resource.id, actor))

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
              nodes:
                board_nodes(@nodes, board_reactions_by_node(@reactions, to_string(@current_user.id))),
              edges: board_edges(@edges),
              current_user_id: @current_user.id,
              file_url: @file_url,
              total_pages: @resource.page_count,
              annotations: board_annotations(@annotations),
              workspace_id: @workspace_id,
              resource_id: @resource.id
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
        %{"node_type" => node_type, "position_x" => px, "position_y" => py} = params,
        socket
      ) do
    actor = socket.assigns.current_user

    input = %{
      resource_id: socket.assigns.resource.id,
      node_type: String.to_existing_atom(node_type),
      position_x: px,
      position_y: py,
      page_number: Map.get(params, "page_number"),
      content: Map.get(params, "content"),
      label: Map.get(params, "label")
    }

    result =
      Studysync.Board.Node
      |> Ash.Changeset.for_create(:create, input, actor: actor)
      |> Ash.create(actor: actor)

    case result do
      {:ok, _node} -> {:noreply, reload_board(socket)}
      {:error, _} -> {:noreply, socket}
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
      {:ok, _edge} -> {:noreply, reload_board(socket)}
      {:error, _} -> {:noreply, socket}
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

  def handle_event("toggle_reaction", %{"node_id" => node_id, "emoji" => emoji}, socket) do
    actor = socket.assigns.current_user
    resource_id = socket.assigns.resource.id

    existing =
      Studysync.Board.Reaction
      |> Ash.Query.filter(node_id == ^node_id and user_id == ^actor.id and emoji == ^emoji)
      |> Ash.read_one!(actor: actor)

    case existing do
      nil ->
        Studysync.Board.Reaction
        |> Ash.Changeset.for_create(:react, %{node_id: node_id, emoji: emoji}, actor: actor)
        |> Ash.create!(actor: actor)

      reaction ->
        Ash.destroy!(reaction, action: :unreact, actor: actor)
    end

    BoardPubSub.broadcast_reaction_toggled(resource_id)
    {:noreply, reload_reactions(socket)}
  end

  def handle_event("cursor_moved", %{"x" => x, "y" => y}, socket) do
    actor = socket.assigns.current_user
    resource_id = socket.assigns.resource.id

    BoardPubSub.broadcast_cursor_moved(
      resource_id,
      to_string(actor.id),
      to_string(actor.email),
      x,
      y
    )

    {:noreply, socket}
  end

  def handle_event("edge_label_updated", %{"id" => id, "label" => label}, socket) do
    actor = socket.assigns.current_user
    resource_id = socket.assigns.resource.id

    case Board.get_edge(id, actor: actor) do
      {:ok, edge} ->
        edge
        |> Ash.Changeset.for_update(:set_label, %{label: label}, actor: actor)
        |> Ash.update(actor: actor)

        BoardPubSub.broadcast_edge_updated(resource_id)
        {:noreply, reload_board(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  # --- PubSub ---

  def handle_info({event, %{resource_id: resource_id}}, socket)
      when event in [
             :node_created,
             :node_moved,
             :node_deleted,
             :edge_created,
             :edge_deleted,
             :edge_updated
           ] and
             resource_id == socket.assigns.resource.id do
    {:noreply, reload_board(socket)}
  end

  def handle_info({:reaction_toggled, %{resource_id: resource_id}}, socket)
      when resource_id == socket.assigns.resource.id do
    {:noreply, reload_reactions(socket)}
  end

  def handle_info(
        {:cursor_moved, %{user_id: uid, email: email, x: x, y: y, resource_id: rid}},
        socket
      )
      when rid == socket.assigns.resource.id do
    {:noreply, push_event(socket, "peer_cursor", %{user_id: uid, email: email, x: x, y: y})}
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

  defp reload_reactions(socket) do
    actor = socket.assigns.current_user
    resource_id = socket.assigns.resource.id
    assign(socket, :reactions, load_reactions(resource_id, actor))
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

  defp load_reactions(resource_id, actor) do
    node_ids =
      Studysync.Board.Node
      |> Ash.Query.filter(resource_id == ^resource_id)
      |> Ash.Query.select([:id])
      |> Ash.read!(actor: actor)
      |> Enum.map(& &1.id)

    case node_ids do
      [] ->
        []

      ids ->
        Studysync.Board.Reaction
        |> Ash.Query.filter(node_id in ^ids)
        |> Ash.read!(actor: actor)
    end
  end

  defp board_here_now(resource_id) do
    (@presence_topic_prefix <> resource_id)
    |> Presence.list()
    |> map_size()
  end

  defp board_nodes(nodes, reactions_by_node) do
    Enum.map(nodes, fn n ->
      %{
        id: n.id,
        node_type: to_string(n.node_type),
        page_number: n.page_number,
        label: n.label,
        content: n.content,
        position_x: n.position_x,
        position_y: n.position_y,
        user_id: n.user_id,
        reactions: Map.get(reactions_by_node, to_string(n.id), [])
      }
    end)
  end

  defp board_reactions_by_node(reactions, current_user_id) do
    reactions
    |> Enum.group_by(&to_string(&1.node_id))
    |> Map.new(fn {node_id, rs} ->
      emoji_groups =
        rs
        |> Enum.group_by(& &1.emoji)
        |> Enum.map(fn {emoji, emoji_rs} ->
          %{
            emoji: emoji,
            count: length(emoji_rs),
            reacted_by_me: Enum.any?(emoji_rs, &(to_string(&1.user_id) == current_user_id))
          }
        end)

      {node_id, emoji_groups}
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

  defp board_annotations(annotations) do
    Enum.map(annotations, fn a ->
      %{
        id: a.id,
        page_number: a.page_number,
        text: a.text,
        type: to_string(a.type)
      }
    end)
  end
end
