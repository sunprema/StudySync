defmodule Studysync.Sprints do
  @moduledoc """
  Domain for timed reading sprints (Slice 21).

  A sprint anchors a timed focus session to a page range of a resource.
  Members join; when the timer expires, a compare-notes reveal surfaces
  all annotations created during the sprint window.
  """

  use Ash.Domain,
    otp_app: :studysync,
    extensions: [AshPhoenix]

  require Ash.Query

  alias Studysync.Sprints.Sprint
  alias Studysync.Sprints.SprintMember

  resources do
    resource Sprint do
      define :start_sprint,
        action: :start,
        args: [:resource_id, :workspace_id, :start_page, :end_page, :duration_minutes]

      define :end_sprint, action: :end_sprint
      define :list_sprints, action: :read
      define :get_sprint, action: :read, get_by: [:id]
    end

    resource SprintMember do
      define :join_sprint, action: :join, args: [:sprint_id]
      define :list_sprint_members, action: :read
    end
  end

  @doc """
  Returns the active sprint for `resource_id`, or `nil` if none exists.
  """
  @spec active_sprint(binary()) :: Studysync.Sprints.Sprint.t() | nil
  def active_sprint(resource_id) do
    Sprint
    |> Ash.Query.filter(resource_id == ^resource_id and status == :active)
    |> Ash.Query.load(:members)
    |> Ash.read_one!(authorize?: false)
  end

  @doc """
  Returns true if `user_id` is a member of `sprint`.
  """
  @spec sprint_member?(Studysync.Sprints.Sprint.t(), binary()) :: boolean()
  def sprint_member?(%Sprint{members: members}, user_id) when is_list(members) do
    Enum.any?(members, &(&1.user_id == user_id))
  end

  def sprint_member?(%Sprint{id: sprint_id}, user_id) do
    SprintMember
    |> Ash.Query.filter(sprint_id == ^sprint_id and user_id == ^user_id)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> false
      _ -> true
    end
  end

  @doc """
  Returns annotations created within the sprint window on the sprint's page
  range, grouped by `user_id`. Used by the compare-notes modal.

  Each entry in the returned list is `{user_id, email, [annotation]}`.
  """
  @spec compare_notes(Studysync.Sprints.Sprint.t()) :: list()
  def compare_notes(%Sprint{} = sprint) do
    member_ids =
      (sprint.members || [])
      |> Enum.map(& &1.user_id)

    # The annotations table uses `timestamp WITHOUT time zone` (UTC values stored
    # without tz info). Ash sends DateTime filter values as `timestamptz`, which
    # Postgres then converts to the session timezone before comparing — breaking
    # when the session is not UTC. Using fragment/1 with NaiveDateTime bypasses
    # Ash's type-casting so Postgrex sends the value as `timestamp` OID 1114,
    # making the comparison type-homogeneous and session-timezone-safe.
    started_naive = DateTime.to_naive(sprint.inserted_at)

    base_query =
      Studysync.Annotations.Annotation
      |> Ash.Query.filter(
        resource_id == ^sprint.resource_id and
          page_number >= ^sprint.start_page and
          page_number <= ^sprint.end_page and
          user_id in ^member_ids
      )
      |> Ash.Query.filter(fragment("inserted_at >= ?", ^started_naive))

    # Only apply the upper-bound filter for ended sprints. For active sprints,
    # omitting the upper bound avoids Postgres/BEAM clock skew.
    query =
      case sprint.ended_at do
        nil ->
          base_query

        ended_at ->
          ended_naive = DateTime.to_naive(ended_at)
          Ash.Query.filter(base_query, fragment("inserted_at <= ?", ^ended_naive))
      end

    query
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.load(:user)
    |> Ash.read!(authorize?: false)
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {user_id, annotations} ->
      email =
        annotations
        |> List.first()
        |> Map.get(:user)
        |> case do
          nil -> "Unknown"
          u -> to_string(u.email)
        end

      {user_id, email, annotations}
    end)
    |> Enum.sort_by(fn {_id, email, _anns} -> email end)
  end
end
