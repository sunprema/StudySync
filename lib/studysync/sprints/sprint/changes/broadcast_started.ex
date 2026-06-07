defmodule Studysync.Sprints.Sprint.Changes.BroadcastStarted do
  use Ash.Resource.Change

  alias Studysync.Sprints.PubSub

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _cs, sprint ->
      PubSub.broadcast_sprint_started(sprint.resource_id, sprint)
      {:ok, sprint}
    end)
  end
end
