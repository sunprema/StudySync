defmodule Studysync.Progress.MilestoneMarker.Changes.SetMilestoneAttributes do
  @moduledoc """
  Lifts the `:create_milestone` action's arguments onto the changeset's
  attributes.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.change_attribute(
      :resource_id,
      Ash.Changeset.get_argument(changeset, :resource_id)
    )
    |> Ash.Changeset.change_attribute(
      :page_number,
      Ash.Changeset.get_argument(changeset, :page_number)
    )
    |> Ash.Changeset.change_attribute(
      :position,
      Ash.Changeset.get_argument(changeset, :position)
    )
    |> Ash.Changeset.change_attribute(:label, Ash.Changeset.get_argument(changeset, :label))
  end
end
