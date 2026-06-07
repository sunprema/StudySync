defmodule Studysync.Sprints.SprintMember.Changes.BroadcastJoined do
  use Ash.Resource.Change

  alias Studysync.Sprints.PubSub
  alias Studysync.Sprints.Sprint

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _cs, member ->
      case Ash.get(Sprint, member.sprint_id, authorize?: false) do
        {:ok, sprint} ->
          PubSub.broadcast_sprint_joined(sprint.resource_id, sprint)

        _ ->
          :ok
      end

      {:ok, member}
    end)
  end
end
