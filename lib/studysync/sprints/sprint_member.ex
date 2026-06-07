defmodule Studysync.Sprints.SprintMember do
  @moduledoc """
  Records that a user has joined a reading sprint.
  One row per `(sprint_id, user_id)` pair — enforced by a unique DB index.
  """

  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Sprints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sprint_members"
    repo Studysync.Repo

    references do
      reference :sprint, on_delete: :delete
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :join do
      argument :sprint_id, :uuid, allow_nil?: false

      change relate_actor(:user)
      change set_attribute(:sprint_id, arg(:sprint_id))
      change set_attribute(:joined_at, &DateTime.utc_now/0)
      change Studysync.Sprints.SprintMember.Changes.BroadcastJoined
    end
  end

  policies do
    bypass actor_attribute_equals(:role, nil) do
      authorize_if always()
    end

    policy action(:join) do
      authorize_if Studysync.Sprints.Checks.ActorIsSprintWorkspaceMember
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :joined_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :sprint, Studysync.Sprints.Sprint, allow_nil?: false
    belongs_to :user, Studysync.Accounts.User, allow_nil?: false
  end

  identities do
    identity :one_per_user_per_sprint, [:sprint_id, :user_id]
  end
end
