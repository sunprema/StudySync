defmodule Studysync.Sprints.PubSub do
  @moduledoc """
  Resource-scoped PubSub for sprint events (Slice 21).

  Rides the same per-resource topic as annotations and progress so the open
  reader, which already subscribes, receives sprint signals without a new
  subscription.
  """

  @pubsub Studysync.PubSub

  def broadcast_sprint_started(resource_id, sprint) when is_binary(resource_id) do
    span(resource_id, :sprint_started, fn ->
      Phoenix.PubSub.broadcast!(@pubsub, topic(resource_id), {:sprint_started, sprint})
    end)
  end

  def broadcast_sprint_joined(resource_id, sprint) when is_binary(resource_id) do
    span(resource_id, :sprint_joined, fn ->
      Phoenix.PubSub.broadcast!(@pubsub, topic(resource_id), {:sprint_joined, sprint})
    end)
  end

  def broadcast_sprint_ended(resource_id, sprint) when is_binary(resource_id) do
    span(resource_id, :sprint_ended, fn ->
      Phoenix.PubSub.broadcast!(@pubsub, topic(resource_id), {:sprint_ended, sprint})
    end)
  end

  def topic(resource_id) when is_binary(resource_id), do: "resource:#{resource_id}"

  defp span(resource_id, event, fun) do
    :telemetry.span(
      [:studysync, :pubsub, :broadcast],
      %{topic: topic(resource_id), event: event},
      fn ->
        result = fun.()
        {result, %{topic: topic(resource_id), event: event}}
      end
    )
  end
end
