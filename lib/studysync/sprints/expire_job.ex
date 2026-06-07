defmodule Studysync.Sprints.ExpireJob do
  @moduledoc """
  Oban worker that fires when a sprint's timer expires.

  Scheduled at `started_at + duration_minutes` by `ScheduleExpiry`.
  Transitions the sprint to `:ended` and broadcasts `:sprint_ended` so all
  open readers receive the compare-notes signal.

  Idempotent: if the sprint was already ended (e.g. the starter ended it
  early), the job exits with `:ok`.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Studysync.Sprints.Sprint

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sprint_id" => sprint_id}}) do
    case Ash.get(Sprint, sprint_id, authorize?: false) do
      {:ok, %Sprint{status: :ended}} ->
        :ok

      {:ok, %Sprint{} = sprint} ->
        sprint
        |> Ash.Changeset.for_update(:end_sprint, %{})
        |> Ash.update!(authorize?: false)

        :ok

      {:error, %Ash.Error.Query.NotFound{}} ->
        :ok
    end
  end
end
