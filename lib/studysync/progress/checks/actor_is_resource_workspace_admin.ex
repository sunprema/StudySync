defmodule Studysync.Progress.Checks.ActorIsResourceWorkspaceAdmin do
  @moduledoc """
  Authorizes the actor only if they hold an active admin membership in the
  workspace that owns the resource targeted by the changeset's `resource_id`
  argument or attribute.

  Mirrors `Studysync.Annotations.Checks.ActorIsResourceWorkspaceMember`, but
  requires the `:admin` role — milestone placement is admin-only per Slice 12.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_), do: "actor is an active admin of the resource's workspace"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    resource_id =
      Ash.Changeset.get_argument(changeset, :resource_id) ||
        Ash.Changeset.get_attribute(changeset, :resource_id)

    admin?(actor, resource_id)
  end

  def match?(_actor, _context, _opts), do: false

  defp admin?(_actor, nil), do: false

  defp admin?(actor, resource_id) do
    with {:ok, %{workspace_id: workspace_id}} <-
           Studysync.Library.Resource
           |> Ash.Query.filter(id == ^resource_id)
           |> Ash.read_one(authorize?: false),
         workspace_id when not is_nil(workspace_id) <- workspace_id,
         {:ok, %{} = _membership} <-
           Studysync.Workspaces.Membership
           |> Ash.Query.filter(
             workspace_id == ^workspace_id and
               user_id == ^actor.id and
               role == :admin and
               status == :active
           )
           |> Ash.read_one(authorize?: false) do
      true
    else
      _ -> false
    end
  end
end
