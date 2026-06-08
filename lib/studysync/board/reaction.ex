defmodule Studysync.Board.Reaction do
  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Board,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "board_reactions"
    repo Studysync.Repo

    references do
      reference :node, on_delete: :delete
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :react do
      argument :node_id, :uuid, allow_nil?: false
      argument :emoji, :string, allow_nil?: false
      change set_attribute(:node_id, arg(:node_id))
      change set_attribute(:emoji, arg(:emoji))
      change relate_actor(:user)
    end

    destroy :unreact do
      require_atomic? false
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     exists(
                       node.resource.workspace.memberships,
                       user_id == ^actor(:id) and status == :active
                     )
                   )
    end

    policy action(:react) do
      authorize_if Studysync.Board.Checks.ActorIsNodeWorkspaceMember
    end

    policy action(:unreact) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :emoji, :string do
      allow_nil? false
      public? true
      constraints max_length: 8
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :node, Studysync.Board.Node, allow_nil?: false
    belongs_to :user, Studysync.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_reaction, [:node_id, :user_id, :emoji]
  end
end
