defmodule Studysync.Sprints.Checks.ActorIsSprintStarter do
  @moduledoc """
  Authorizes the actor only if they started the sprint being acted on.
  Used to gate the `:end_sprint` action so only the starter (or the Oban
  worker with no actor, bypassed via the `bypass` policy) can end early.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_), do: "actor started this sprint"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{changeset: %Ash.Changeset{data: sprint}}, _opts) do
    sprint.started_by_id == actor.id
  end

  def match?(_actor, _context, _opts), do: false
end
