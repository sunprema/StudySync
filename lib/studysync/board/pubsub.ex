defmodule Studysync.Board.PubSub do
  @moduledoc """
  Resource-scoped PubSub for board events (Slice 22).

  Topic: `"resource:<resource_id>:board"` — separate from the annotation
  and chat topics so subscribers that don't care about board changes aren't
  woken up.

  Payloads carry only the minimum needed (id + resource_id). Subscribers
  refetch through Ash so read policies stay honest (CLAUDE.md §8.4).
  """

  @pubsub Studysync.PubSub

  def subscribe(resource_id) when is_binary(resource_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(resource_id))
  end

  def unsubscribe(resource_id) when is_binary(resource_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(resource_id))
  end

  def broadcast_node_created(resource_id, node_id)
      when is_binary(resource_id) and is_binary(node_id) do
    span(topic(resource_id), :node_created, fn ->
      Phoenix.PubSub.broadcast_from!(
        @pubsub,
        self(),
        topic(resource_id),
        {:node_created, %{id: node_id, resource_id: resource_id}}
      )
    end)
  end

  def broadcast_node_moved(resource_id, node_id)
      when is_binary(resource_id) and is_binary(node_id) do
    span(topic(resource_id), :node_moved, fn ->
      Phoenix.PubSub.broadcast_from!(
        @pubsub,
        self(),
        topic(resource_id),
        {:node_moved, %{id: node_id, resource_id: resource_id}}
      )
    end)
  end

  def broadcast_node_deleted(resource_id, node_id)
      when is_binary(resource_id) and is_binary(node_id) do
    span(topic(resource_id), :node_deleted, fn ->
      Phoenix.PubSub.broadcast_from!(
        @pubsub,
        self(),
        topic(resource_id),
        {:node_deleted, %{id: node_id, resource_id: resource_id}}
      )
    end)
  end

  def broadcast_edge_created(resource_id, edge_id)
      when is_binary(resource_id) and is_binary(edge_id) do
    span(topic(resource_id), :edge_created, fn ->
      Phoenix.PubSub.broadcast_from!(
        @pubsub,
        self(),
        topic(resource_id),
        {:edge_created, %{id: edge_id, resource_id: resource_id}}
      )
    end)
  end

  def broadcast_edge_deleted(resource_id, edge_id)
      when is_binary(resource_id) and is_binary(edge_id) do
    span(topic(resource_id), :edge_deleted, fn ->
      Phoenix.PubSub.broadcast_from!(
        @pubsub,
        self(),
        topic(resource_id),
        {:edge_deleted, %{id: edge_id, resource_id: resource_id}}
      )
    end)
  end

  def topic(resource_id) when is_binary(resource_id), do: "resource:#{resource_id}:board"

  defp span(topic, event, fun) do
    :telemetry.span(
      [:studysync, :pubsub, :broadcast],
      %{topic: topic, event: event},
      fn ->
        result = fun.()
        {result, %{topic: topic, event: event}}
      end
    )
  end
end
