defmodule Studysync.Activity.PubSub do
  @moduledoc """
  Workspace-scoped PubSub for the activity feed (Slice 8).

  Topic convention: `"workspace:" <> workspace_id`. The library page's Recent
  rail subscribes here and the annotation/reply broadcast changes fan out
  here as well as on the per-resource topic that the reader uses
  (`Studysync.Annotations.PubSub`). Resource-topic and workspace-topic
  broadcasts are intentionally separate concerns: the reader only cares
  about its open resource; the dashboard cares about anything in the
  workspace.

  Payload carries minimum shape (id + workspace scope) — never raw
  resource structs (CLAUDE.md §8.4). Subscribers refetch through Ash so
  read policies stay honest per actor.
  """

  alias Studysync.Library.Resource

  @pubsub Studysync.PubSub

  @doc "Subscribe the calling process to a workspace's activity events."
  def subscribe(workspace_id) when is_binary(workspace_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(workspace_id))
  end

  @doc "Unsubscribe the calling process from a workspace's activity events."
  def unsubscribe(workspace_id) when is_binary(workspace_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(workspace_id))
  end

  @doc """
  Resolve `resource_id` to a workspace and broadcast that an annotation was
  created. Uses `broadcast_from!` so the originating process — which already
  applied an optimistic insert — does not double-handle its own event.
  """
  def broadcast_annotation_created(resource_id, annotation_id)
      when is_binary(resource_id) and is_binary(annotation_id) do
    case workspace_id_for_resource(resource_id) do
      nil ->
        :ok

      workspace_id ->
        span(topic(workspace_id), :activity_annotation_created, fn ->
          Phoenix.PubSub.broadcast_from!(
            @pubsub,
            self(),
            topic(workspace_id),
            {:activity_annotation_created,
             %{annotation_id: annotation_id, workspace_id: workspace_id}}
          )
        end)
    end
  end

  @doc """
  Broadcast a reply-created activity event for the workspace the parent
  resource belongs to.
  """
  def broadcast_reply_created(resource_id, reply_id)
      when is_binary(resource_id) and is_binary(reply_id) do
    case workspace_id_for_resource(resource_id) do
      nil ->
        :ok

      workspace_id ->
        span(topic(workspace_id), :activity_reply_created, fn ->
          Phoenix.PubSub.broadcast_from!(
            @pubsub,
            self(),
            topic(workspace_id),
            {:activity_reply_created, %{reply_id: reply_id, workspace_id: workspace_id}}
          )
        end)
    end
  end

  @doc """
  Broadcast a stamp-applied activity event for the workspace the parent
  resource belongs to (Slice 13).
  """
  def broadcast_stamp_applied(resource_id, milestone_id, stamp_id)
      when is_binary(resource_id) and is_binary(milestone_id) and is_binary(stamp_id) do
    case workspace_id_for_resource(resource_id) do
      nil ->
        :ok

      workspace_id ->
        span(topic(workspace_id), :activity_stamp_applied, fn ->
          Phoenix.PubSub.broadcast_from!(
            @pubsub,
            self(),
            topic(workspace_id),
            {:activity_stamp_applied,
             %{
               stamp_id: stamp_id,
               milestone_id: milestone_id,
               workspace_id: workspace_id
             }}
          )
        end)
    end
  end

  def topic(workspace_id) when is_binary(workspace_id), do: "workspace:#{workspace_id}"

  defp workspace_id_for_resource(resource_id) do
    case Ash.get(Resource, resource_id, authorize?: false) do
      {:ok, %{workspace_id: workspace_id}} -> workspace_id
      _ -> nil
    end
  end

  # Slice 15.5 — broadcast fan-out latency. Subscriber count isn't directly
  # available from Phoenix.PubSub, so the metadata only carries topic + event.
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
