defmodule Studysync.Board.Node.Changes.BroadcastNodeCreated do
  use Ash.Resource.Change

  alias Studysync.Board.PubSub, as: BoardPubSub

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, node ->
      BoardPubSub.broadcast_node_created(node.resource_id, node.id)
      {:ok, node}
    end)
  end
end
