defmodule Studysync.Annotations.AnnotationComment do
  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Annotations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "annotation_comments"
    repo Studysync.Repo

    references do
      reference :annotation, on_delete: :delete
      reference :user, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :reply do
      argument :annotation_id, :uuid, allow_nil?: false
      argument :body, :string, allow_nil?: false

      change set_attribute(:is_ai_response, false)
      change relate_actor(:user)
      change set_attribute(:annotation_id, arg(:annotation_id))
      change set_attribute(:body, arg(:body))
      change Studysync.Annotations.AnnotationComment.Changes.BroadcastReply
    end
  end

  policies do
    policy action(:reply) do
      authorize_if Studysync.Annotations.Checks.ActorCanReplyToAnnotation
    end

    policy action_type(:read) do
      # Workspace-visible parent annotation: any active workspace member can read.
      authorize_if expr(
                     annotation.visibility == :workspace and
                       exists(
                         annotation.resource.workspace.memberships,
                         user_id == ^actor(:id) and status == :active
                       )
                   )

      # Private parent annotation: only the annotation's author.
      authorize_if expr(
                     annotation.visibility == :private and
                       annotation.user_id == ^actor(:id)
                   )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :body, :string do
      allow_nil? false
      public? true
      constraints max_length: 4_000
    end

    attribute :is_ai_response, :boolean do
      allow_nil? false
      public? true
      default false
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :annotation, Studysync.Annotations.Annotation, allow_nil?: false
    belongs_to :user, Studysync.Accounts.User, allow_nil?: true
  end
end
