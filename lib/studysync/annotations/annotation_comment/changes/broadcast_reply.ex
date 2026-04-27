defmodule Studysync.Annotations.AnnotationComment.Changes.BroadcastReply do
  @moduledoc """
  After a reply is committed, fan out a `:reply_created` event on the parent
  annotation's resource topic. The reply itself doesn't carry `resource_id`
  — we resolve it from the parent annotation, which is always loadable.

  Payload is `%{id, annotation_id, resource_id}`. Subscribers refetch
  through Ash to honour read policies (CLAUDE.md §8.4).
  """
  use Ash.Resource.Change

  alias Studysync.Annotations.Annotation
  alias Studysync.Annotations.PubSub

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, reply ->
      annotation = Ash.get!(Annotation, reply.annotation_id, authorize?: false)
      PubSub.broadcast_reply_created(annotation.resource_id, reply.annotation_id, reply.id)
      {:ok, reply}
    end)
  end
end
