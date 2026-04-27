defmodule Studysync.Progress.RubberStamp.Changes.BroadcastStamped do
  @moduledoc """
  After a stamp is committed, broadcast on the parent resource topic so any
  open reader patches its milestone panel + canvas count, and on the
  workspace activity topic so the library Recent rail prepends a
  `:stamped` event (Slice 8 / Slice 13).

  Payload carries only ids + scope (CLAUDE.md §8.4); subscribers refetch
  through Ash so per-actor read policies stay honest.
  """
  use Ash.Resource.Change

  alias Studysync.Activity.PubSub, as: ActivityPubSub
  alias Studysync.Progress.MilestoneMarker
  alias Studysync.Progress.PubSub, as: ProgressPubSub

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, stamp ->
      milestone = Ash.get!(MilestoneMarker, stamp.milestone_id, authorize?: false)

      ProgressPubSub.broadcast_stamp_applied(
        milestone.resource_id,
        milestone.id,
        stamp.id
      )

      ActivityPubSub.broadcast_stamp_applied(
        milestone.resource_id,
        milestone.id,
        stamp.id
      )

      {:ok, stamp}
    end)
  end
end
