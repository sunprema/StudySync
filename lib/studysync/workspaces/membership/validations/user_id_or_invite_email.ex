defmodule Studysync.Workspaces.Membership.Validations.UserIdOrInviteEmail do
  @moduledoc """
  Every membership row anchors to either an existing user (`user_id`) or a
  pending invitee email (`invite_email`). At least one must be set.
  """
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def supports(_opts), do: [Ash.Changeset]

  @impl true
  def validate(changeset, _opts, _context) do
    user_id = Ash.Changeset.get_attribute(changeset, :user_id)
    invite_email = Ash.Changeset.get_attribute(changeset, :invite_email)

    case {user_id, invite_email} do
      {nil, nil} ->
        {:error, message: "must be linked to a user or an invite_email"}

      _ ->
        :ok
    end
  end
end
