defmodule Studysync.Progress.Checks.ActorIsMilestoneWorkspaceMember do
  @moduledoc """
  Authorizes the actor only if they hold an active membership in the
  workspace that owns the milestone targeted by the changeset's
  `milestone_id` argument.

  Used by `RubberStamp.:apply_stamp` — any active workspace member can stamp
  a milestone in their workspace; stamping is a participation signal, not an
  admin-gated action.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_), do: "actor is an active member of the milestone's workspace"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    milestone_id =
      Ash.Changeset.get_argument(changeset, :milestone_id) ||
        Ash.Changeset.get_attribute(changeset, :milestone_id)

    member?(actor, milestone_id)
  end

  def match?(_actor, _context, _opts), do: false

  defp member?(_actor, nil), do: false

  defp member?(actor, milestone_id) do
    with {:ok, %{resource: %{workspace_id: workspace_id}}} <-
           Studysync.Progress.MilestoneMarker
           |> Ash.Query.filter(id == ^milestone_id)
           |> Ash.Query.load(:resource)
           |> Ash.read_one(authorize?: false),
         workspace_id when not is_nil(workspace_id) <- workspace_id,
         {:ok, %{} = _membership} <-
           Studysync.Workspaces.Membership
           |> Ash.Query.filter(
             workspace_id == ^workspace_id and
               user_id == ^actor.id and
               status == :active
           )
           |> Ash.read_one(authorize?: false) do
      true
    else
      _ -> false
    end
  end
end
