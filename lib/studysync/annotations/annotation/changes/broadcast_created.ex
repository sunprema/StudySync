defmodule Studysync.Annotations.Annotation.Changes.BroadcastCreated do
  @moduledoc """
  After a new annotation is committed, fan out two broadcasts:

    * `:annotation_created` on the resource topic — readers patch their
      margin column.
    * `:activity_annotation_created` on the workspace topic — the library's
      Recent rail (Slice 8) prepends a fresh activity item.

  Payloads carry only ids + scope (CLAUDE.md §8.4); subscribers refetch
  through Ash so per-actor policies are honoured.
  """
  use Ash.Resource.Change

  alias Studysync.Activity.PubSub, as: ActivityPubSub
  alias Studysync.Annotations.PubSub

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, annotation ->
      PubSub.broadcast_annotation_created(annotation.resource_id, annotation.id)
      ActivityPubSub.broadcast_annotation_created(annotation.resource_id, annotation.id)
      {:ok, annotation}
    end)
  end
end
