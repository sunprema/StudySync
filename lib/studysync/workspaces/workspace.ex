defmodule Studysync.Workspaces.Workspace do
  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Workspaces,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspaces"
    repo Studysync.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name]

      change Studysync.Workspaces.Workspace.Changes.AddCreatorAsAdmin
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if expr(exists(memberships, user_id == ^actor(:id) and status == :active))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :memberships, Studysync.Workspaces.Membership
  end
end
