defmodule Studysync.Workspaces.Membership.Changes.SendInviteEmail do
  @moduledoc """
  After-action hook on `Membership.invite` (and `:resend_invite`) that emails
  the invitee a signed acceptance link. Failures to deliver do not roll back
  the action — the pending row is the system-of-record; the email is just
  notification.
  """

  use Ash.Resource.Change

  require Ash.Query
  require Logger

  alias Studysync.Workspaces.Membership.Senders.SendInviteEmail

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, membership ->
      recipient =
        Ash.Changeset.get_argument(changeset, :email) || resolve_recipient(membership)

      with {:ok, recipient} <- ensure_recipient(recipient, membership),
           {:ok, workspace} <- load_workspace(membership.workspace_id) do
        case SendInviteEmail.send(membership, workspace, recipient) do
          {:ok, _result} ->
            Logger.info("[invite] mail delivered to #{recipient}")

          {:error, reason} ->
            Logger.error("[invite] mail delivery failed: #{inspect(reason)}")
        end
      else
        :no_recipient ->
          Logger.error("[invite] could not resolve recipient for membership=#{membership.id}")

        :no_workspace ->
          Logger.error("[invite] could not load workspace #{membership.workspace_id}")
      end

      {:ok, membership}
    end)
  end

  defp ensure_recipient(nil, _membership), do: :no_recipient
  defp ensure_recipient(recipient, _membership), do: {:ok, recipient}

  defp resolve_recipient(%{invite_email: email}) when not is_nil(email), do: email

  defp resolve_recipient(%{user_id: user_id}) when not is_nil(user_id) do
    Studysync.Accounts.User
    |> Ash.Query.filter(id == ^user_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{email: email}} -> email
      _ -> nil
    end
  end

  defp resolve_recipient(_), do: nil

  defp load_workspace(workspace_id) do
    Studysync.Workspaces.Workspace
    |> Ash.Query.filter(id == ^workspace_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> :no_workspace
      {:ok, workspace} -> {:ok, workspace}
      {:error, _} -> :no_workspace
    end
  end
end
