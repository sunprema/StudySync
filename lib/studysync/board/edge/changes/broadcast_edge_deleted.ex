defmodule Studysync.Board.Edge.Changes.BroadcastEdgeDeleted do
  use Ash.Resource.Change

  alias Studysync.Board.PubSub, as: BoardPubSub

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, edge ->
      BoardPubSub.broadcast_edge_deleted(edge.resource_id, edge.id)
      {:ok, edge}
    end)
  end
end
