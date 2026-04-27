defmodule Studysync.Workspaces.Membership do
  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Workspaces,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "memberships"
    repo Studysync.Repo

    references do
      reference :workspace, on_delete: :delete
      reference :user, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :create do
      # Direct creation. Reachable only via authorize?: false (used by
      # Workspace.Changes.AddCreatorAsAdmin and tests). External callers
      # should use :invite instead.
      accept [:workspace_id, :user_id, :invite_email, :role, :status]
    end

    create :invite do
      argument :workspace_id, :uuid, allow_nil?: false
      argument :email, :ci_string, allow_nil?: false

      change Studysync.Workspaces.Membership.Changes.ResolveInvite
    end

    update :accept do
      accept []
      change set_attribute(:status, :active)
    end
  end

  policies do
    # No policy on action(:create) — defaults to forbidden, so direct creation
    # is server-only via authorize?: false.

    policy action(:invite) do
      authorize_if Studysync.Workspaces.Checks.ActorIsWorkspaceAdmin
    end

    policy action(:accept) do
      authorize_if expr(user_id == ^actor(:id) and status == :pending)
    end

    policy action_type(:read) do
      authorize_if expr(
                     exists(
                       workspace.memberships,
                       user_id == ^actor(:id) and status == :active
                     )
                   )
    end
  end

  validations do
    validate Studysync.Workspaces.Membership.Validations.UserIdOrInviteEmail,
      on: [:create]
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:admin, :member]
      default :member
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:pending, :active]
      default :pending
    end

    attribute :invite_email, :ci_string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :workspace, Studysync.Workspaces.Workspace, allow_nil?: false
    belongs_to :user, Studysync.Accounts.User, allow_nil?: true
  end

  identities do
    identity :unique_user_per_workspace, [:workspace_id, :user_id]
  end
end
