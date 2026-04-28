defmodule Studysync.Chat.PubSub do
  @moduledoc """
  Resource-scoped PubSub for transient chat (Slice 18).

  Topic convention: `"resource:" <> resource_id <> ":chat"`. Kept separate from
  the annotation topic (`Studysync.Annotations.PubSub`) so subscribers that
  only care about annotations/replies/stamps don't see chat traffic.

  CLAUDE.md §8.4 normally requires broadcasting "minimum payload + refetch
  through Ash". Chat carves out: there is no DB to refetch from, so the full
  `%Message{}` struct rides on the topic. This is the only place in the
  codebase that broadcasts a full domain value.
  """

  alias Studysync.Chat.Message

  @pubsub Studysync.PubSub

  @doc "Subscribe the calling process to a resource's chat topic."
  def subscribe(resource_id) when is_binary(resource_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(resource_id))
  end

  @doc "Unsubscribe the calling process from a resource's chat topic."
  def unsubscribe(resource_id) when is_binary(resource_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(resource_id))
  end

  @doc """
  Broadcast a chat message to all subscribers EXCEPT the sender (who already
  rendered it optimistically). Wrapped in `:telemetry.span/3` to match the
  observability pattern in `Annotations.PubSub` (Slice 15.5).
  """
  def broadcast_message_sent(%Message{resource_id: resource_id} = message) do
    span(topic(resource_id), :message_sent, fn ->
      Phoenix.PubSub.broadcast_from!(
        @pubsub,
        self(),
        topic(resource_id),
        {:chat_message, message}
      )
    end)
  end

  def topic(resource_id) when is_binary(resource_id), do: "resource:#{resource_id}:chat"

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
