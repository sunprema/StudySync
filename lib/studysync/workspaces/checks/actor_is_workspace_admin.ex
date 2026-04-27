defmodule Studysync.Workspaces.Checks.ActorIsWorkspaceAdmin do
  @moduledoc """
  Authorizes the actor only if they hold an active admin membership for the
  workspace targeted by the changeset's `workspace_id` argument or attribute.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_), do: "actor is an active admin of the workspace"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    workspace_id =
      Ash.Changeset.get_argument(changeset, :workspace_id) ||
        Ash.Changeset.get_attribute(changeset, :workspace_id)

    actor_admin?(actor, workspace_id)
  end

  def match?(_actor, _context, _opts), do: false

  defp actor_admin?(_actor, nil), do: false

  defp actor_admin?(actor, workspace_id) do
    Studysync.Workspaces.Membership
    |> Ash.Query.filter(
      workspace_id == ^workspace_id and
        user_id == ^actor.id and
        role == :admin and
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
