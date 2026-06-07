defmodule Studysync.Sprints.Sprint.Changes.ScheduleExpiry do
  @moduledoc """
  After a sprint is committed, enqueue the `ExpireJob` to fire at
  `started_at + duration_minutes`. Uses Oban's `scheduled_at` option so
  the job sits in the queue until its moment, not sooner.
  """
  use Ash.Resource.Change

  alias Studysync.Sprints.ExpireJob

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _cs, sprint ->
      run_at = DateTime.add(sprint.inserted_at, sprint.duration_minutes * 60, :second)

      %{sprint_id: sprint.id, resource_id: sprint.resource_id}
      |> ExpireJob.new(scheduled_at: run_at)
      |> Oban.insert()

      {:ok, sprint}
    end)
  end
end
