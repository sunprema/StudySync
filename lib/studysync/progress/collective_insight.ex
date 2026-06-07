defmodule Studysync.Progress.CollectiveInsight do
  @moduledoc """
  An AI-generated synthesis card created when three or more distinct workspace
  members independently annotate the same page of a resource.

  One insight per `(resource_id, page_number)` pair — enforced by a unique DB
  index so a race between two concurrent writes can't produce duplicates.

  Creation is internal-only (via the `CollectiveInsightJob` Oban worker).
  Workspace members can read their resource's insights via Ash policies.
  """

  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Progress,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "collective_insights"
    repo Studysync.Repo

    references do
      reference :resource, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create_insight do
      argument :resource_id, :uuid, allow_nil?: false
      argument :page_number, :integer, allow_nil?: false
      argument :synthesis, :string, allow_nil?: false
      argument :contributor_ids, {:array, :uuid}, allow_nil?: false
      argument :contributing_annotation_ids, {:array, :uuid}, allow_nil?: false

      change set_attribute(:resource_id, arg(:resource_id))
      change set_attribute(:page_number, arg(:page_number))
      change set_attribute(:synthesis, arg(:synthesis))
      change set_attribute(:contributor_ids, arg(:contributor_ids))
      change set_attribute(:contributing_annotation_ids, arg(:contributing_annotation_ids))
      change Studysync.Progress.CollectiveInsight.Changes.BroadcastInsightReady
    end
  end

  policies do
    # Creation goes through the Oban worker with no actor — bypass policies.
    bypass actor_attribute_equals(:role, nil) do
      authorize_if always()
    end

    policy action(:create_insight) do
      authorize_if always()
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

    attribute :page_number, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :synthesis, :string do
      allow_nil? false
      public? true
    end

    attribute :contributor_ids, {:array, :uuid} do
      allow_nil? false
      public? true
      default []
    end

    attribute :contributing_annotation_ids, {:array, :uuid} do
      allow_nil? false
      public? true
      default []
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :resource, Studysync.Library.Resource, allow_nil?: false
  end

  identities do
    # One insight per page per resource — dedup guard at the DB level.
    identity :one_per_page, [:resource_id, :page_number]
  end
end
