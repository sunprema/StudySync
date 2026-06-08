defmodule Studysync.Board do
  @moduledoc """
  Domain for the collaborative concept map board (Slice 22).

  Any active workspace member can create, move, and delete nodes and edges
  on the board for a given resource. Changes are broadcast via
  `Studysync.Board.PubSub` so all open sessions stay in sync.
  """

  use Ash.Domain,
    otp_app: :studysync,
    extensions: [AshPhoenix]

  resources do
    resource Studysync.Board.Node do
      define :list_nodes, action: :read
      define :get_node, action: :read, get_by: [:id]

      define :create_node,
        action: :create,
        args: [:resource_id, :node_type, :position_x, :position_y]

      define :move_node, action: :move, args: [:position_x, :position_y]
      define :delete_node, action: :delete
    end

    resource Studysync.Board.Edge do
      define :list_edges, action: :read
      define :get_edge, action: :read, get_by: [:id]

      define :create_edge,
        action: :create,
        args: [:resource_id, :source_id, :target_id]

      define :delete_edge, action: :delete
    end
  end
end
