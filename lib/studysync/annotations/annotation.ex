defmodule Studysync.Annotations.Annotation do
  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Annotations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "annotations"
    repo Studysync.Repo

    references do
      reference :resource, on_delete: :delete
      reference :user, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :create_comment do
      argument :resource_id, :uuid, allow_nil?: false
      argument :page_number, :integer, allow_nil?: false
      argument :rect, :map, allow_nil?: false
      argument :text, :string, allow_nil?: false
      argument :body, :string, allow_nil?: false
      argument :visibility, :atom, allow_nil?: true

      change set_attribute(:type, :comment)
      change relate_actor(:user)
      change Studysync.Annotations.Annotation.Changes.SetCommentAttributes
      change Studysync.Annotations.Annotation.Changes.BroadcastCreated
    end
  end

  policies do
    policy action(:create_comment) do
      authorize_if Studysync.Annotations.Checks.ActorIsResourceWorkspaceMember
    end

    policy action_type(:read) do
      # Workspace-visible annotations: any active workspace member can read.
      authorize_if expr(
                     visibility == :workspace and
                       exists(
                         resource.workspace.memberships,
                         user_id == ^actor(:id) and status == :active
                       )
                   )

      # Private annotations: only the author.
      authorize_if expr(visibility == :private and user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:comment, :question, :puzzle, :ai_response]
    end

    attribute :color, :string do
      allow_nil? false
      public? true
      default "peach"
    end

    attribute :visibility, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:private, :workspace]
      default :workspace
    end

    attribute :text, :string do
      allow_nil? false
      public? true
      constraints max_length: 4_000
    end

    attribute :body, :string do
      allow_nil? false
      public? true
      constraints max_length: 4_000
    end

    attribute :page_number, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    # Rect is normalized to the page (values 0.0–1.0) so it survives zoom
    # and re-rendering. Keys: %{"x" => float, "y" => float, "width" => float,
    # "height" => float}.
    attribute :rect, :map do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :resource, Studysync.Library.Resource, allow_nil?: false
    belongs_to :user, Studysync.Accounts.User, allow_nil?: true

    has_many :replies, Studysync.Annotations.AnnotationComment do
      sort inserted_at: :asc
    end
  end

  aggregates do
    count :reply_count, :replies
  end
end
