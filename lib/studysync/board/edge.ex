defmodule Studysync.Board.Edge do
  @moduledoc """
  A directed connection between two `Board.Node` records (Slice 22).

  The `[:source_id, :target_id]` identity prevents duplicate edges between
  the same pair of nodes.
  """

  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Board,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "board_edges"
    repo Studysync.Repo

    references do
      reference :source, on_delete: :delete
      reference :target, on_delete: :delete
      reference :resource, on_delete: :delete
      reference :user, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :create do
      argument :resource_id, :uuid, allow_nil?: false
      argument :source_id, :uuid, allow_nil?: false
      argument :target_id, :uuid, allow_nil?: false

      change set_attribute(:resource_id, arg(:resource_id))
      change set_attribute(:source_id, arg(:source_id))
      change set_attribute(:target_id, arg(:target_id))
      change relate_actor(:user)
      change Studysync.Board.Edge.Changes.BroadcastEdgeCreated
    end

    destroy :delete do
      require_atomic? false

      change Studysync.Board.Edge.Changes.BroadcastEdgeDeleted
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if Studysync.Board.Checks.ActorIsResourceWorkspaceMember
    end

    policy action(:delete) do
      authorize_if expr(
                     exists(
                       resource.workspace.memberships,
                       user_id == ^actor(:id) and status == :active
                     )
                   )
    end

    policy action_type(:read) do
      authorize_if expr(
                     exists(
                       resource.workspace.memberships,
                       user_id == ^actor(:id) and status == :active
                     )
                   )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :label, :string do
      allow_nil? true
      public? true
      constraints max_length: 100
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :source, Studysync.Board.Node, allow_nil?: false
    belongs_to :target, Studysync.Board.Node, allow_nil?: false
    belongs_to :resource, Studysync.Library.Resource, allow_nil?: false
    belongs_to :user, Studysync.Accounts.User, allow_nil?: true
  end

  identities do
    identity :unique_edge, [:source_id, :target_id]
  end
end
