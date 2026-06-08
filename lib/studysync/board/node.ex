defmodule Studysync.Board.Node do
  @moduledoc """
  A concept node on a resource's collaborative concept map board (Slice 22).

  Any active workspace member can create, move, or delete any node — the
  board is intentionally fully collaborative, like a shared whiteboard.
  """

  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Board,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "board_nodes"
    repo Studysync.Repo

    references do
      reference :resource, on_delete: :delete
      reference :user, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :create do
      argument :resource_id, :uuid, allow_nil?: false
      argument :node_type, :atom, allow_nil?: false
      argument :page_number, :integer, allow_nil?: true
      argument :label, :string, allow_nil?: true
      argument :content, :map, allow_nil?: true
      argument :position_x, :float, allow_nil?: false
      argument :position_y, :float, allow_nil?: false

      change set_attribute(:resource_id, arg(:resource_id))
      change set_attribute(:node_type, arg(:node_type))
      change set_attribute(:page_number, arg(:page_number))
      change set_attribute(:label, arg(:label))
      change set_attribute(:content, arg(:content))
      change set_attribute(:position_x, arg(:position_x))
      change set_attribute(:position_y, arg(:position_y))
      change relate_actor(:user)
      change Studysync.Board.Node.Changes.BroadcastNodeCreated
    end

    update :move do
      require_atomic? false

      argument :position_x, :float, allow_nil?: false
      argument :position_y, :float, allow_nil?: false

      change set_attribute(:position_x, arg(:position_x))
      change set_attribute(:position_y, arg(:position_y))
      change Studysync.Board.Node.Changes.BroadcastNodeMoved
    end

    destroy :delete do
      require_atomic? false

      change Studysync.Board.Node.Changes.BroadcastNodeDeleted
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if Studysync.Board.Checks.ActorIsResourceWorkspaceMember
    end

    policy action(:move) do
      authorize_if expr(
                     exists(
                       resource.workspace.memberships,
                       user_id == ^actor(:id) and status == :active
                     )
                   )
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

    attribute :node_type, :atom do
      allow_nil? false
      public? true
      default :page
      constraints one_of: [:page, :youtube, :text, :quote, :link]
    end

    attribute :page_number, :integer do
      allow_nil? true
      public? true
      constraints min: 1
    end

    attribute :label, :string do
      allow_nil? true
      public? true
      constraints max_length: 200
    end

    attribute :content, :map do
      allow_nil? true
      public? true
    end

    attribute :position_x, :float do
      allow_nil? false
      public? true
    end

    attribute :position_y, :float do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :resource, Studysync.Library.Resource, allow_nil?: false
    belongs_to :user, Studysync.Accounts.User, allow_nil?: true
  end
end
