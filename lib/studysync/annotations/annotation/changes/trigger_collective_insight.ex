defmodule Studysync.Annotations.Annotation.Changes.TriggerCollectiveInsight do
  @moduledoc """
  After a new annotation is committed, enqueue a `CollectiveInsightJob` for
  its `(resource_id, page_number)` pair. The job checks whether three or more
  distinct users have annotated that page and, if so, calls the AI to produce
  a GROUP LENS card.

  The job is idempotent (exits immediately when an insight already exists),
  so firing it on every annotation is safe even if many writers are active
  on the same page at once.
  """
  use Ash.Resource.Change

  alias Studysync.AI.CollectiveInsightJob

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, annotation ->
      %{resource_id: annotation.resource_id, page_number: annotation.page_number}
      |> CollectiveInsightJob.new()
      |> Oban.insert()

      {:ok, annotation}
    end)
  end
end
