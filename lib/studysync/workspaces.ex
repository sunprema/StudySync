defmodule Studysync.Workspaces do
  use Ash.Domain,
    otp_app: :studysync,
    extensions: [AshPhoenix]

  require Ash.Query

  alias Studysync.Workspaces.Membership

  resources do
    resource Studysync.Workspaces.Workspace do
      define :create_workspace, action: :create, args: [:name]
      define :list_workspaces, action: :read
      define :get_workspace, action: :read, get_by: [:id]
    end

    resource Studysync.Workspaces.Membership do
      define :list_memberships, action: :read
      define :accept_invite, action: :accept
      define :resend_invite_action, action: :resend_invite
    end
  end

  @doc """
  Invite an email to a workspace, idempotently.

  - If the email is already an active member → `{:error, :already_member}`.
  - If the email already has a pending membership in this workspace → re-fires
    the invitation email and returns the existing pending membership.
  - Otherwise → creates a new pending membership and emails the invitee.

  Authorization: requires the actor to be an active admin of the workspace
  (enforced by the underlying `:invite` / `:resend_invite` actions).
  """
  def invite_member(workspace_id, email, opts) do
    actor = Keyword.fetch!(opts, :actor)
    email_str = to_string(email)

    case find_existing_membership(workspace_id, email_str) do
      {:ok, %{status: :active}} ->
        {:error, :already_member}

      {:ok, %{status: :pending} = pending} ->
        case pending
             |> Ash.Changeset.for_update(:resend_invite, %{}, actor: actor)
             |> Ash.update() do
          {:ok, updated} -> {:ok, updated}
          {:error, error} -> {:error, error}
        end

      {:ok, nil} ->
        Membership
        |> Ash.Changeset.for_create(
          :invite,
          %{workspace_id: workspace_id, email: email_str},
          actor: actor
        )
        |> Ash.create()
    end
  end

  def invite_member!(workspace_id, email, opts) do
    case invite_member(workspace_id, email, opts) do
      {:ok, membership} ->
        membership

      {:error, :already_member} ->
        raise Ash.Error.Invalid, errors: [already_member_error()]

      {:error, %{__exception__: true} = error} ->
        raise error

      {:error, error} ->
        raise Ash.Error.to_error_class(error)
    end
  end

  @doc "Public for the LiveView so it can render a friendly flash."
  def already_member_error,
    do: %Ash.Error.Changes.InvalidArgument{
      field: :email,
      message: "is already a member of this workspace"
    }

  defp find_existing_membership(workspace_id, email) do
    user_id = lookup_user_id(email)

    base = Ash.Query.filter(Membership, workspace_id == ^workspace_id)

    candidates =
      if user_id do
        base
        |> Ash.Query.filter(invite_email == ^email or user_id == ^user_id)
        |> Ash.read!(authorize?: false)
      else
        base
        |> Ash.Query.filter(invite_email == ^email)
        |> Ash.read!(authorize?: false)
      end

    {:ok, List.first(candidates)}
  end

  defp lookup_user_id(email) do
    Studysync.Accounts.User
    |> Ash.Query.filter(email == ^email)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{id: id}} -> id
      _ -> nil
    end
  end
end
