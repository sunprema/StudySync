defmodule Studysync.Annotations.Annotation.Changes.BroadcastCreated do
  @moduledoc """
  After a new annotation is committed, fan out an `:annotation_created`
  event on the resource topic so any open reader patches its margin column.

  Payload is `%{id, resource_id}` — subscribers refetch through Ash so
  policies are honoured per actor (CLAUDE.md §8.4).
  """
  use Ash.Resource.Change

  alias Studysync.Annotations.PubSub

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, annotation ->
      PubSub.broadcast_annotation_created(annotation.resource_id, annotation.id)
      {:ok, annotation}
    end)
  end
end
