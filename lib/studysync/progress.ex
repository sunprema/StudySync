defmodule Studysync.Progress do
  @moduledoc """
  Domain for reading-progress artefacts: admin-placed milestones (Slice 12)
  and the user-applied rubber stamps that mark them complete (Slice 13).

  Code-interface entry points are defined here so callers stay one alias deep
  (e.g. `Studysync.Progress.create_milestone/4`).
  """

  use Ash.Domain,
    otp_app: :studysync,
    extensions: [AshPhoenix]

  resources do
    resource Studysync.Progress.MilestoneMarker do
      define :list_milestones, action: :read
      define :get_milestone, action: :read, get_by: [:id]

      define :create_milestone,
        action: :create_milestone,
        args: [:resource_id, :page_number, :position, :label]
    end

    resource Studysync.Progress.RubberStamp do
      define :list_stamps, action: :read

      define :apply_stamp,
        action: :apply_stamp,
        args: [:milestone_id, {:optional, :note}]
    end
  end
end
