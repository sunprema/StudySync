defmodule Studysync.Progress do
  @moduledoc """
  Domain for reading-progress artefacts: admin-placed milestones (Slice 12),
  user-applied rubber stamps (Slice 13), and collective insight cards (Slice 20).

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

    resource Studysync.Progress.CollectiveInsight do
      define :list_collective_insights, action: :read

      define :create_insight,
        action: :create_insight,
        args: [
          :resource_id,
          :page_number,
          :synthesis,
          :contributor_ids,
          :contributing_annotation_ids
        ]
    end

    resource Studysync.Progress.RubberStamp do
      define :list_stamps, action: :read

      define :apply_stamp,
        action: :apply_stamp,
        args: [:milestone_id, {:optional, :note}]
    end
  end
end
