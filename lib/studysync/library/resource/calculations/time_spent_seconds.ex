defmodule Studysync.Library.Resource.Calculations.TimeSpentSeconds do
  @moduledoc """
  Per-user time spent on a resource, in seconds — proxied by the gap between
  the user's earliest and latest annotation on that resource.

  Without explicit session tracking, this gap is the most defensible
  approximation: it answers "how long has this reader been engaging with
  this book," not "how many seconds did their eyes touch the page." A real
  telemetry-driven number is a perf-pass concern (Slice 15).

  Returns `0` when the user has 0 or 1 annotation (no measurable interval).
  """
  use Ash.Resource.Calculation

  require Ash.Query

  alias Studysync.Annotations.Annotation

  @impl true
  def calculate(records, _opts, %{arguments: %{user_id: user_id}}) when not is_nil(user_id) do
    resource_ids = Enum.map(records, & &1.id)
    spans = spans_per_resource(resource_ids, user_id)

    Enum.map(records, fn resource ->
      Map.get(spans, resource.id, 0)
    end)
  end

  def calculate(records, _opts, _context), do: Enum.map(records, fn _ -> 0 end)

  defp spans_per_resource([], _user_id), do: %{}

  defp spans_per_resource(resource_ids, user_id) do
    Annotation
    |> Ash.Query.filter(resource_id in ^resource_ids and user_id == ^user_id)
    |> Ash.Query.select([:resource_id, :inserted_at])
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.resource_id, & &1.inserted_at)
    |> Map.new(fn {rid, timestamps} ->
      span =
        case timestamps do
          [] -> 0
          [_] -> 0
          many -> DateTime.diff(Enum.max(many, DateTime), Enum.min(many, DateTime), :second)
        end

      {rid, span}
    end)
  end
end
