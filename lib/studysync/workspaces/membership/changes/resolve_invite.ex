defmodule Studysync.Workspaces.Membership.Changes.ResolveInvite do
  @moduledoc """
  Translates the `:invite` action's `workspace_id` and `email` arguments into
  attributes. Looks up an existing user by email — if one is found we set
  `user_id`; otherwise the membership is held against `invite_email` until the
  invitee registers and accepts.
  """
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    workspace_id = Ash.Changeset.get_argument(changeset, :workspace_id)
    email = Ash.Changeset.get_argument(changeset, :email)

    changeset =
      changeset
      |> Ash.Changeset.change_attribute(:workspace_id, workspace_id)
      |> Ash.Changeset.change_attribute(:status, :pending)
      |> Ash.Changeset.change_attribute(:role, :member)

    case lookup_user(email) do
      nil -> Ash.Changeset.change_attribute(changeset, :invite_email, email)
      user -> Ash.Changeset.change_attribute(changeset, :user_id, user.id)
    end
  end

  defp lookup_user(email) do
    Studysync.Accounts.User
    |> Ash.Query.for_read(:get_by_email, %{email: email})
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
