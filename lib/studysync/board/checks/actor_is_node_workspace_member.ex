defmodule Studysync.Board.Checks.ActorIsNodeWorkspaceMember do
  @moduledoc """
  Authorizes an actor to perform a create action on a Board resource whose
  node_id argument identifies the node. Walks node → resource → workspace
  and verifies active membership without traversing relationships on the
  not-yet-persisted record.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_), do: "actor is an active member of the node's resource workspace"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    node_id = Ash.Changeset.get_argument(changeset, :node_id)
    member_via_node?(actor, node_id)
  end

  def match?(_actor, _context, _opts), do: false

  defp member_via_node?(_actor, nil), do: false

  defp member_via_node?(actor, node_id) do
    with {:ok, %{resource_id: resource_id}} <-
           Studysync.Board.Node
           |> Ash.Query.filter(id == ^node_id)
           |> Ash.Query.select([:resource_id])
           |> Ash.read_one(authorize?: false),
         resource_id when not is_nil(resource_id) <- resource_id,
         {:ok, %{workspace_id: workspace_id}} <-
           Studysync.Library.Resource
           |> Ash.Query.filter(id == ^resource_id)
           |> Ash.Query.select([:workspace_id])
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
