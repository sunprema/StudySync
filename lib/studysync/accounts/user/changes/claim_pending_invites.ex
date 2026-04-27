defmodule Studysync.Accounts.User.Changes.ClaimPendingInvites do
  @moduledoc """
  After a user is registered, attach them to any `Membership` rows that were
  created against their email before they had an account. Status stays
  `:pending` — the user must still explicitly accept via the invite link;
  this just lets `/invites/:token` resolve to the right user.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Studysync.Workspaces.Membership

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      query =
        Membership
        |> Ash.Query.filter(invite_email == ^user.email and is_nil(user_id))

      _ =
        Ash.bulk_update(query, :claim_for_user, %{user_id: user.id},
          authorize?: false,
          return_errors?: false,
          notify?: false
        )

      {:ok, user}
    end)
  end
end
