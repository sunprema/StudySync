defmodule Studysync.Workspaces.Workspace.Changes.AddCreatorAsAdmin do
  @moduledoc """
  After creating a workspace, give the actor an active admin membership.
  Used as the workspace creation hook so the creator can immediately read,
  invite, and use the workspace they just made.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: actor}) when not is_nil(actor) do
    Ash.Changeset.after_action(changeset, fn _changeset, workspace ->
      Studysync.Workspaces.Membership
      |> Ash.Changeset.for_create(
        :create,
        %{
          workspace_id: workspace.id,
          user_id: actor.id,
          role: :admin,
          status: :active
        },
        authorize?: false
      )
      |> Ash.create!()

      {:ok, workspace}
    end)
  end

  def change(changeset, _opts, _context), do: changeset
end
