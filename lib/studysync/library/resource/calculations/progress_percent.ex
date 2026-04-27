defmodule Studysync.Library.Resource.Calculations.ProgressPercent do
  @moduledoc """
  Per-user reading progress on a resource, as an integer percentage.

  Progress is approximated by the deepest page the user has annotated,
  divided by the resource's `page_count`. Until we ship explicit
  page-view tracking (a later perf-pass concern), the furthest annotation
  is the strongest signal we have that a user has actually read that far.

  Returns `0` when the user has no annotations on the resource.
  """
  use Ash.Resource.Calculation

  require Ash.Query

  alias Studysync.Annotations.Annotation

  @impl true
  def calculate(records, _opts, %{arguments: %{user_id: user_id}}) when not is_nil(user_id) do
    resource_ids = Enum.map(records, & &1.id)
    max_pages = max_pages_per_resource(resource_ids, user_id)

    Enum.map(records, fn resource ->
      max = Map.get(max_pages, resource.id, 0)
      pc = resource.page_count || 0

      cond do
        pc <= 0 -> 0
        max <= 0 -> 0
        true -> min(100, trunc(max * 100 / pc))
      end
    end)
  end

  def calculate(records, _opts, _context), do: Enum.map(records, fn _ -> 0 end)

  defp max_pages_per_resource([], _user_id), do: %{}

  # Slice 14 audit: `authorize?: false` is intentional. Progress is "how far
  # has this reader gotten", which counts a user's *own* annotations regardless
  # of visibility — a private highlight on page 80 is still evidence the user
  # read to page 80. We only project `[:resource_id, :page_number]`; annotation
  # body/text/snippet never enter this code path, so private content stays
  # private even though the page-number metadata of one's own annotations
  # contributes to one's own visible progress %.
  defp max_pages_per_resource(resource_ids, user_id) do
    Annotation
    |> Ash.Query.filter(resource_id in ^resource_ids and user_id == ^user_id)
    |> Ash.Query.select([:resource_id, :page_number])
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.resource_id, & &1.page_number)
    |> Map.new(fn {rid, pages} -> {rid, Enum.max(pages, fn -> 0 end)} end)
  end
end
