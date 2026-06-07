defmodule Studysync.Sprints.Sprint do
  @moduledoc """
  A timed reading sprint anchored to a page range of a resource.

  Created by any active workspace member. When three or more conditions are
  met — start_page, end_page, duration_minutes — the `ExpireJob` is scheduled
  and a `:sprint_started` PubSub event fires. Members join; when the timer
  expires the sprint transitions to `:ended` and a compare-notes reveal opens
  in all open readers.
  """

  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Sprints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sprints"
    repo Studysync.Repo

    references do
      reference :resource, on_delete: :delete
      reference :started_by, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :start do
      argument :resource_id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid, allow_nil?: false
      argument :start_page, :integer, allow_nil?: false
      argument :end_page, :integer, allow_nil?: false
      argument :duration_minutes, :integer, allow_nil?: false

      change relate_actor(:started_by, allow_nil?: true)
      change set_attribute(:resource_id, arg(:resource_id))
      change set_attribute(:workspace_id, arg(:workspace_id))
      change set_attribute(:start_page, arg(:start_page))
      change set_attribute(:end_page, arg(:end_page))
      change set_attribute(:duration_minutes, arg(:duration_minutes))
      change set_attribute(:status, :active)

      change fn cs, _ ->
        Ash.Changeset.force_change_attribute(cs, :started_at, DateTime.utc_now())
      end

      change Studysync.Sprints.Sprint.Changes.AddStarterAsMember
      change Studysync.Sprints.Sprint.Changes.ScheduleExpiry
      change Studysync.Sprints.Sprint.Changes.BroadcastStarted
    end

    update :end_sprint do
      require_atomic? false

      change set_attribute(:status, :ended)

      change fn cs, _ ->
        Ash.Changeset.force_change_attribute(cs, :ended_at, DateTime.utc_now())
      end

      change Studysync.Sprints.Sprint.Changes.BroadcastEnded
    end
  end

  policies do
    # Oban worker ends sprints without an actor.
    bypass actor_attribute_equals(:role, nil) do
      authorize_if always()
    end

    policy action(:start) do
      authorize_if Studysync.Sprints.Checks.ActorIsSprintWorkspaceMember
    end

    policy action(:end_sprint) do
      authorize_if Studysync.Sprints.Checks.ActorIsSprintStarter
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :start_page, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :end_page, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :duration_minutes, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 120
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:active, :ended]
      default :active
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :ended_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :resource, Studysync.Library.Resource, allow_nil?: false
    belongs_to :workspace, Studysync.Workspaces.Workspace, allow_nil?: false
    belongs_to :started_by, Studysync.Accounts.User, allow_nil?: true

    has_many :members, Studysync.Sprints.SprintMember do
      destination_attribute :sprint_id
    end
  end
end
