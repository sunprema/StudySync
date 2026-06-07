defmodule Studysync.Library.Resource do
  use Ash.Resource,
    otp_app: :studysync,
    domain: Studysync.Library,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "library_resources"
    repo Studysync.Repo

    references do
      reference :workspace, on_delete: :delete
      reference :uploaded_by, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :upload do
      argument :workspace_id, :uuid, allow_nil?: false
      argument :title, :string, allow_nil?: false
      argument :upload, :map, allow_nil?: false

      change relate_actor(:uploaded_by, allow_nil?: true)
      change Studysync.Library.Resource.Changes.StoreUpload
    end

    create :import_from_url do
      argument :workspace_id, :uuid, allow_nil?: false
      argument :title, :string, allow_nil?: false
      argument :url, :string, allow_nil?: false

      change relate_actor(:uploaded_by, allow_nil?: true)
      change Studysync.Library.Resource.Changes.FetchUrl
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     exists(
                       workspace.memberships,
                       user_id == ^actor(:id) and status == :active
                     )
                   )
    end

    policy action(:upload) do
      authorize_if Studysync.Workspaces.Checks.ActorIsWorkspaceMember
    end

    policy action(:import_from_url) do
      authorize_if Studysync.Workspaces.Checks.ActorIsWorkspaceMember
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200
    end

    attribute :file_path, :string do
      allow_nil? false
      public? true
    end

    attribute :page_count, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :workspace, Studysync.Workspaces.Workspace, allow_nil?: false
    belongs_to :uploaded_by, Studysync.Accounts.User, allow_nil?: true

    has_many :annotations, Studysync.Annotations.Annotation
  end

  calculations do
    calculate :progress_percent,
              :integer,
              Studysync.Library.Resource.Calculations.ProgressPercent do
      argument :user_id, :uuid, allow_nil?: false
    end

    calculate :time_spent_seconds,
              :integer,
              Studysync.Library.Resource.Calculations.TimeSpentSeconds do
      argument :user_id, :uuid, allow_nil?: false
    end

    calculate :avg_progress_percent,
              :integer,
              Studysync.Library.Resource.Calculations.AvgProgressPercent
  end
end
