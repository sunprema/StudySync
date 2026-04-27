defmodule Studysync.Annotations.AnnotationComment.Changes.BroadcastReply do
  @moduledoc """
  After a reply is committed, fan out two broadcasts:

    * `:reply_created` on the parent annotation's resource topic — the
      reader patches the open thread.
    * `:activity_reply_created` on the workspace topic — the library's
      Recent rail (Slice 8) prepends an activity item.

  The reply itself doesn't carry `resource_id`; we resolve it from the
  parent annotation. Payloads are minimum needed (CLAUDE.md §8.4) so
  subscribers refetch through Ash and honour read policies.
  """
  use Ash.Resource.Change

  alias Studysync.Activity.PubSub, as: ActivityPubSub
  alias Studysync.Annotations.Annotation
  alias Studysync.Annotations.PubSub

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, reply ->
      annotation = Ash.get!(Annotation, reply.annotation_id, authorize?: false)
      PubSub.broadcast_reply_created(annotation.resource_id, reply.annotation_id, reply.id)
      ActivityPubSub.broadcast_reply_created(annotation.resource_id, reply.id)
      {:ok, reply}
    end)
  end
end
