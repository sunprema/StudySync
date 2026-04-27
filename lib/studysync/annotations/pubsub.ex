defmodule Studysync.Annotations.PubSub do
  @moduledoc """
  Resource-scoped PubSub for annotation events.

  Topic convention (CLAUDE.md §4.4): `"resource:" <> resource_id`.

  Payloads carry the minimum needed for a subscriber to act — id and scope
  — and never the raw resource struct. Subscribers refetch through Ash so
  authorization stays honest (CLAUDE.md §8.4).
  """

  @pubsub Studysync.PubSub

  @doc "Subscribe the calling process to a resource's annotation events."
  def subscribe(resource_id) when is_binary(resource_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(resource_id))
  end

  @doc "Unsubscribe the calling process from a resource's annotation events."
  def unsubscribe(resource_id) when is_binary(resource_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(resource_id))
  end

  # `broadcast_from!/4` skips the calling process so the originator never
  # receives its own broadcast — handles the optimistic-UI/PubSub double-fire
  # without per-handler de-dup. The after_action change always runs in the
  # caller's process, so `self()` here is the LiveView (or test) that wrote.
  def broadcast_annotation_created(resource_id, annotation_id)
      when is_binary(resource_id) and is_binary(annotation_id) do
    Phoenix.PubSub.broadcast_from!(
      @pubsub,
      self(),
      topic(resource_id),
      {:annotation_created, %{id: annotation_id, resource_id: resource_id}}
    )
  end

  def broadcast_reply_created(resource_id, annotation_id, reply_id)
      when is_binary(resource_id) and is_binary(annotation_id) and is_binary(reply_id) do
    Phoenix.PubSub.broadcast_from!(
      @pubsub,
      self(),
      topic(resource_id),
      {:reply_created, %{id: reply_id, annotation_id: annotation_id, resource_id: resource_id}}
    )
  end

  def topic(resource_id) when is_binary(resource_id), do: "resource:#{resource_id}"
end
