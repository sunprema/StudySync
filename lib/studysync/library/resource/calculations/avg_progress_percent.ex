defmodule Studysync.Library.Resource.Calculations.AvgProgressPercent do
  @moduledoc """
  Workspace-level average reading progress on a resource, as an integer
  percentage.

  Computed from the per-user max page (the same signal `progress_percent`
  uses) averaged across every user who has annotated the resource. Users
  with zero annotations are not counted — the dashboard treats them as
  "hasn't started" through their reader card, not as a 0% drag on the
  group's pace.

  Returns `0` when no one has annotated the resource yet.
  """
  use Ash.Resource.Calculation

  require Ash.Query

  alias Studysync.Annotations.Annotation

  @impl true
  def calculate(records, _opts, _context) do
    resource_ids = Enum.map(records, & &1.id)
    avgs = avg_per_resource(resource_ids)

    Enum.map(records, fn resource ->
      pc = resource.page_count || 0
      avg_max = Map.get(avgs, resource.id, 0)

      if pc > 0 and avg_max > 0 do
        trunc(avg_max * 100 / pc)
      else
        0
      end
    end)
  end

  defp avg_per_resource([]), do: %{}

  defp avg_per_resource(resource_ids) do
    Annotation
    |> Ash.Query.filter(resource_id in ^resource_ids)
    |> Ash.Query.select([:resource_id, :user_id, :page_number])
    |> Ash.read!(authorize?: false)
    |> Enum.reject(&is_nil(&1.user_id))
    |> Enum.group_by(&{&1.resource_id, &1.user_id}, & &1.page_number)
    |> Enum.map(fn {{rid, _uid}, pages} ->
      {rid, Enum.max(pages, fn -> 0 end)}
    end)
    |> Enum.group_by(fn {rid, _max} -> rid end, fn {_rid, max} -> max end)
    |> Map.new(fn {rid, maxes} ->
      count = length(maxes)
      avg = if count > 0, do: Enum.sum(maxes) / count, else: 0
      {rid, avg}
    end)
  end
end
