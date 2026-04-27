defmodule Studysync.Library.Resource.Calculations.AvgProgressPercent do
  @moduledoc """
  Workspace-level average reading progress on a resource, as an integer
  percentage.

  Computed as the mean of every active workspace member's individual
  `progress_percent` on the resource. Members who haven't annotated
  contribute `0` to the average — they're shown on the timeline as a pin
  at 0%, and they should pull the avg toward 0 in the same way. A
  workspace where one of two members has read to 100% reports `50%`, not
  `100%`.

  Per-user percentages are clamped to 100 before averaging, so a stale
  annotation past `page_count` (e.g. a re-uploaded PDF with fewer pages)
  can't push the group avg above 100%.

  Returns `0` when the resource has no page count or its workspace has no
  active members.
  """
  use Ash.Resource.Calculation

  require Ash.Query

  alias Studysync.Annotations.Annotation
  alias Studysync.Workspaces.Membership

  @impl true
  def calculate(records, _opts, _context) do
    resource_ids = Enum.map(records, & &1.id)
    workspace_ids = records |> Enum.map(& &1.workspace_id) |> Enum.uniq()

    max_pages = max_pages_per_resource_user(resource_ids)
    members = active_member_counts(workspace_ids)

    Enum.map(records, fn resource ->
      pc = resource.page_count || 0
      member_count = Map.get(members, resource.workspace_id, 0)
      user_maxes = Map.get(max_pages, resource.id, %{})

      cond do
        pc <= 0 -> 0
        member_count <= 0 -> 0
        true -> avg_percent(user_maxes, pc, member_count)
      end
    end)
  end

  # Each member's individual percentage is `min(100, max_page * 100 / pc)`.
  # Members with no annotations have no entry in `user_maxes` and contribute
  # `0` to the sum (their pin sits at 0% on the timeline). Dividing by the
  # active member count, not the annotator count, makes the avg match the
  # denominator the dashboard's pins show.
  defp avg_percent(user_maxes, pc, member_count) do
    sum_pct =
      user_maxes
      |> Map.values()
      |> Enum.map(fn max_page -> min(100, max_page * 100 / pc) end)
      |> Enum.sum()

    trunc(sum_pct / member_count)
  end

  defp max_pages_per_resource_user([]), do: %{}

  defp max_pages_per_resource_user(resource_ids) do
    Annotation
    |> Ash.Query.filter(resource_id in ^resource_ids)
    |> Ash.Query.select([:resource_id, :user_id, :page_number])
    |> Ash.read!(authorize?: false)
    |> Enum.reject(&is_nil(&1.user_id))
    |> Enum.group_by(& &1.resource_id, &{&1.user_id, &1.page_number})
    |> Map.new(fn {rid, pairs} ->
      {rid,
       pairs
       |> Enum.group_by(fn {uid, _p} -> uid end, fn {_uid, p} -> p end)
       |> Map.new(fn {uid, pages} -> {uid, Enum.max(pages, fn -> 0 end)} end)}
    end)
  end

  defp active_member_counts([]), do: %{}

  defp active_member_counts(workspace_ids) do
    Membership
    |> Ash.Query.filter(workspace_id in ^workspace_ids and status == :active)
    |> Ash.Query.select([:workspace_id])
    |> Ash.read!(authorize?: false)
    |> Enum.frequencies_by(& &1.workspace_id)
  end
end
