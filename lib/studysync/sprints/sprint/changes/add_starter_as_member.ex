defmodule Studysync.Sprints.Sprint.Changes.AddStarterAsMember do
  @moduledoc """
  After a sprint is committed, creates a `SprintMember` record for the actor
  who started it so they are automatically part of their own sprint.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _cs, sprint ->
      if sprint.started_by_id do
        Studysync.Sprints.SprintMember
        |> Ash.Changeset.for_create(:join, %{sprint_id: sprint.id},
          authorize?: false,
          actor: %{id: sprint.started_by_id, role: nil}
        )
        |> Ash.create(authorize?: false)
      end

      {:ok, sprint}
    end)
  end
end
