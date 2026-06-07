defmodule Studysync.Progress.PubSub do
  @moduledoc """
  Resource-scoped PubSub for progress events (Slice 13).

  Piggybacks on the same per-resource topic (`"resource:" <> resource_id`)
  the reader already subscribes to via `Studysync.Annotations.PubSub` — the
  open reader is the canonical surface for milestone + stamp updates, so
  there's no reason to multiply topics.

  Payloads carry the minimum needed (ids + scope); subscribers refetch
  through Ash so per-actor read policies stay honest (CLAUDE.md §8.4).
  """

  @pubsub Studysync.PubSub

  def broadcast_collective_insight_ready(resource_id, insight)
      when is_binary(resource_id) do
    :telemetry.span(
      [:studysync, :pubsub, :broadcast],
      %{topic: topic(resource_id), event: :collective_insight_ready},
      fn ->
        result =
          Phoenix.PubSub.broadcast!(
            @pubsub,
            topic(resource_id),
            {:collective_insight_ready, insight}
          )

        {result, %{topic: topic(resource_id), event: :collective_insight_ready}}
      end
    )
  end

  def broadcast_stamp_applied(resource_id, milestone_id, stamp_id)
      when is_binary(resource_id) and is_binary(milestone_id) and is_binary(stamp_id) do
    :telemetry.span(
      [:studysync, :pubsub, :broadcast],
      %{topic: topic(resource_id), event: :stamp_applied},
      fn ->
        result =
          Phoenix.PubSub.broadcast_from!(
            @pubsub,
            self(),
            topic(resource_id),
            {:stamp_applied,
             %{
               id: stamp_id,
               milestone_id: milestone_id,
               resource_id: resource_id
             }}
          )

        {result, %{topic: topic(resource_id), event: :stamp_applied}}
      end
    )
  end

  def topic(resource_id) when is_binary(resource_id), do: "resource:#{resource_id}"
end
