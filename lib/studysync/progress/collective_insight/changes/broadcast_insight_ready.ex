defmodule Studysync.Progress.CollectiveInsight.Changes.BroadcastInsightReady do
  @moduledoc """
  After a `CollectiveInsight` is committed, broadcast on the resource topic so
  all open readers can append the GROUP LENS card to their margin column.

  Unlike annotation broadcasts — which carry only an id and let the subscriber
  refetch through Ash — the insight struct is broadcast in full here. The
  worker creates insights without an actor, so re-fetching through Ash would
  require bypassing authorization anyway. The struct contains no secrets and is
  workspace-public by policy.
  """
  use Ash.Resource.Change

  alias Studysync.Progress.PubSub

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, insight ->
      PubSub.broadcast_collective_insight_ready(insight.resource_id, insight)
      {:ok, insight}
    end)
  end
end
