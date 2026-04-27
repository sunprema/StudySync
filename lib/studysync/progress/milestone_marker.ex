defmodule Studysync.Progress.MilestoneMarker do
  @moduledoc """
  An admin-placed checkpoint anchored to `(resource, page_number, position)`.

  Milestones structure a workspace's reading flow — "finish chapter 3", "before
  the seminar Tuesday" — and are the anchor that user `RubberStamp`s (Slice 13)
  attach to.

  `position` is normalized to the page (`%{"x" => float, "y" => float}`,
  values 0.0–1.0) so the marker survives zoom and re-rendering, mirroring the
  shape of `Annotation.rect` in §3.4.
  """

  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Progress,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "milestone_markers"
    repo Studysync.Repo

    references do
      reference :resource, on_delete: :delete
      reference :created_by, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :create_milestone do
      argument :resource_id, :uuid, allow_nil?: false
      argument :page_number, :integer, allow_nil?: false
      argument :position, :map, allow_nil?: false
      argument :label, :string, allow_nil?: false

      change relate_actor(:created_by, allow_nil?: true)
      change Studysync.Progress.MilestoneMarker.Changes.SetMilestoneAttributes
    end
  end

  policies do
    policy action(:create_milestone) do
      authorize_if Studysync.Progress.Checks.ActorIsResourceWorkspaceAdmin
    end

    # Any active workspace member can read milestones for resources in their
    # workspace. Admin-only placement is enforced at the create-action policy
    # above; once placed, milestones are workspace-public guideposts.
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

    attribute :page_number, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    # Normalized to the page (values 0.0–1.0). Keys: %{"x" => float, "y" => float}.
    attribute :position, :map do
      allow_nil? false
      public? true
    end

    attribute :label, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :resource, Studysync.Library.Resource, allow_nil?: false
    belongs_to :created_by, Studysync.Accounts.User, allow_nil?: true

    has_many :stamps, Studysync.Progress.RubberStamp do
      destination_attribute :milestone_id
      sort inserted_at: :asc
    end
  end

  aggregates do
    # Slice 13.3 — stamp count per milestone, used in the "X / N readers"
    # label and to derive completion state in the milestone panel.
    count :stamp_count, :stamps

    # Slice 13.4 — flat list of user_ids who've stamped a milestone, for the
    # "have I already stamped this?" check. The full stamper records (with
    # user emails for the avatar cluster) come through `load: [stamps: :user]`.
    list :stamper_user_ids, :stamps, field: :user_id
  end
end
