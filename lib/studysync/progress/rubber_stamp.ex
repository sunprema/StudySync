defmodule Studysync.Progress.RubberStamp do
  @moduledoc """
  A user's completion mark against a `MilestoneMarker`.

  One stamp per `(milestone_id, user_id)` pair (Slice 13). The optional `note`
  lets a reader leave a short impression alongside the stamp ("finally got
  through chapter 3 — Sophronia was harder than I remembered").

  Reads fan out to anyone who can read the parent milestone's resource —
  stamps are workspace-public progress signals, the same way milestones are
  workspace-public guideposts.
  """

  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Progress,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "rubber_stamps"
    repo Studysync.Repo

    references do
      reference :milestone, on_delete: :delete
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :apply_stamp do
      argument :milestone_id, :uuid, allow_nil?: false
      argument :note, :string, allow_nil?: true

      change relate_actor(:user)
      change set_attribute(:milestone_id, arg(:milestone_id))
      change set_attribute(:note, arg(:note))
      change Studysync.Progress.RubberStamp.Changes.BroadcastStamped
    end
  end

  policies do
    policy action(:apply_stamp) do
      authorize_if Studysync.Progress.Checks.ActorIsMilestoneWorkspaceMember
    end

    # Any active workspace member can read stamps for milestones in their
    # workspace. Authorization mirrors `MilestoneMarker.read`: stamps are
    # workspace-public progress markers, not private completion records.
    policy action_type(:read) do
      authorize_if expr(
                     exists(
                       milestone.resource.workspace.memberships,
                       user_id == ^actor(:id) and status == :active
                     )
                   )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :note, :string do
      allow_nil? true
      public? true
      constraints max_length: 1_000
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :milestone, Studysync.Progress.MilestoneMarker, allow_nil?: false
    belongs_to :user, Studysync.Accounts.User, allow_nil?: false
  end

  identities do
    # One stamp per user per milestone — enforced at the DB level so a
    # double-click can't sneak a duplicate row in.
    identity :one_per_user_per_milestone, [:milestone_id, :user_id]
  end
end
