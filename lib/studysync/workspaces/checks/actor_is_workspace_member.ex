defmodule Studysync.Workspaces.Checks.ActorIsWorkspaceMember do
  @moduledoc """
  Authorizes the actor only if they hold an active membership (any role) in
  the workspace targeted by the changeset's `workspace_id` argument or
  attribute.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_), do: "actor is an active member of the workspace"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    workspace_id =
      Ash.Changeset.get_argument(changeset, :workspace_id) ||
        Ash.Changeset.get_attribute(changeset, :workspace_id)

    member?(actor, workspace_id)
  end

  def match?(_actor, _context, _opts), do: false

  defp member?(_actor, nil), do: false

  defp member?(actor, workspace_id) do
    Studysync.Workspaces.Membership
    |> Ash.Query.filter(
      workspace_id == ^workspace_id and
        user_id == ^actor.id and
        status == :active
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> false
      {:ok, _} -> true
      _ -> false
    end
  end
end
