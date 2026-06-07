defmodule Studysync.Sprints.Checks.ActorIsSprintWorkspaceMember do
  @moduledoc """
  Authorizes the actor only if they hold an active membership in the workspace
  that owns the sprint's resource. Reads `workspace_id` from the changeset
  argument or the record being acted on.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_), do: "actor is an active member of the sprint's workspace"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{changeset: %Ash.Changeset{} = cs}, _opts) do
    workspace_id =
      Ash.Changeset.get_argument(cs, :workspace_id) ||
        Ash.Changeset.get_attribute(cs, :workspace_id) ||
        workspace_via_sprint(Ash.Changeset.get_argument(cs, :sprint_id))

    member?(actor, workspace_id)
  end

  def match?(_actor, _context, _opts), do: false

  defp workspace_via_sprint(nil), do: nil

  defp workspace_via_sprint(sprint_id) do
    case Ash.get(Studysync.Sprints.Sprint, sprint_id, authorize?: false) do
      {:ok, sprint} -> sprint.workspace_id
      _ -> nil
    end
  end

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
