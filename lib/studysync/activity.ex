defmodule Studysync.Activity do
  @moduledoc """
  Workspace activity feed (Slice 8).

  Events are derived on read from existing resources rather than persisted
  separately — annotations and replies already carry the truth. This module
  composes them into a workspace-scoped, newest-first stream of
  `Studysync.Activity.Event` structs, with all reads going through Ash so
  per-actor visibility policies are honoured (private annotations, etc.).

  The shape leaves room for `:completed_chapter` (Slice 9) and `:stamped`
  (Slice 13) without changing callers.
  """

  alias Studysync.Activity.Event
  alias Studysync.Annotations
  alias Studysync.Annotations.Annotation
  alias Studysync.Annotations.AnnotationComment
  alias Studysync.Library
  alias Studysync.Library.Resource
  alias Studysync.Progress.RubberStamp

  require Ash.Query

  @default_limit 25
  # We need to mix annotations and replies before slicing to `limit`. Pulling
  # a wider window from each side means we don't drop a recent reply just
  # because its annotation is old. The window is generous; the activity rail
  # is small.
  @window_factor 4

  @doc """
  List the most recent activity events visible to `actor` in `workspace_id`.

  Options: `:actor` (required), `:limit` (default #{@default_limit}).
  """
  @spec list_for_workspace(Ash.UUID.t(), keyword()) :: [Event.t()]
  def list_for_workspace(workspace_id, opts) do
    actor = Keyword.fetch!(opts, :actor)
    limit = Keyword.get(opts, :limit, @default_limit)
    window = limit * @window_factor

    resource_lookup = resources_in_workspace(workspace_id, actor)
    resource_ids = Map.keys(resource_lookup)

    case resource_ids do
      [] ->
        []

      _ ->
        annotations = recent_annotations(resource_ids, actor, window)
        replies = recent_replies(Enum.map(annotations, & &1.id), actor, window)

        annotation_lookup = Map.new(annotations, &{&1.id, &1})

        events =
          Enum.map(annotations, &annotation_to_event(&1, resource_lookup)) ++
            Enum.map(replies, &reply_to_event(&1, annotation_lookup, resource_lookup))

        events
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
        |> Enum.take(limit)
    end
  end

  @doc """
  Build a single event for a freshly-created annotation. Returns
  `{:error, :not_visible}` if the actor cannot read the annotation under
  current policies (e.g. it's private and they're not the author).
  """
  @spec event_from_annotation(Ash.UUID.t(), keyword()) ::
          {:ok, Event.t()} | {:error, :not_visible}
  def event_from_annotation(annotation_id, opts) do
    actor = Keyword.fetch!(opts, :actor)

    with {:ok, annotation} when not is_nil(annotation) <-
           Annotations.get_annotation(annotation_id, actor: actor, load: [:user]),
         {:ok, resource} when not is_nil(resource) <-
           Library.get_resource(annotation.resource_id, actor: actor) do
      {:ok, annotation_to_event(annotation, %{resource.id => resource})}
    else
      _ -> {:error, :not_visible}
    end
  end

  @doc """
  Build a single event for a freshly-created reply. Returns
  `{:error, :not_visible}` if the actor cannot see the parent annotation.
  """
  @spec event_from_reply(Ash.UUID.t(), keyword()) ::
          {:ok, Event.t()} | {:error, :not_visible}
  def event_from_reply(reply_id, opts) do
    actor = Keyword.fetch!(opts, :actor)

    with {:ok, reply} <-
           Ash.get(AnnotationComment, reply_id, actor: actor, load: [:user, :annotation]),
         false <- is_nil(reply),
         %{annotation: %{resource_id: resource_id} = annotation} when not is_nil(annotation) <-
           reply,
         {:ok, resource} when not is_nil(resource) <-
           Library.get_resource(resource_id, actor: actor) do
      annotation_lookup = %{annotation.id => annotation}
      resource_lookup = %{resource.id => resource}
      {:ok, reply_to_event(reply, annotation_lookup, resource_lookup)}
    else
      _ -> {:error, :not_visible}
    end
  end

  @doc """
  Build a single event for a freshly-applied rubber stamp (Slice 13).
  Returns `{:error, :not_visible}` if the actor cannot read the parent
  milestone's resource (which gates stamp visibility too).
  """
  @spec event_from_stamp(Ash.UUID.t(), keyword()) ::
          {:ok, Event.t()} | {:error, :not_visible}
  def event_from_stamp(stamp_id, opts) do
    actor = Keyword.fetch!(opts, :actor)

    with {:ok, stamp} when not is_nil(stamp) <-
           Ash.get(RubberStamp, stamp_id, actor: actor, load: [:user, milestone: [:resource]]),
         %{milestone: %{resource: resource} = milestone} when not is_nil(resource) <- stamp do
      {:ok, stamp_to_event(stamp, milestone, resource)}
    else
      _ -> {:error, :not_visible}
    end
  end

  defp resources_in_workspace(workspace_id, actor) do
    Resource
    |> Ash.Query.filter(workspace_id: workspace_id)
    |> Ash.read!(actor: actor)
    |> Map.new(&{&1.id, &1})
  end

  defp recent_annotations(resource_ids, actor, limit) do
    Annotation
    |> Ash.Query.filter(resource_id in ^resource_ids)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load([:user])
    |> Ash.read!(actor: actor)
  end

  defp recent_replies([], _actor, _limit), do: []

  defp recent_replies(annotation_ids, actor, limit) do
    AnnotationComment
    |> Ash.Query.filter(annotation_id in ^annotation_ids)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load([:user])
    |> Ash.read!(actor: actor)
  end

  defp annotation_to_event(annotation, resource_lookup) do
    resource = Map.get(resource_lookup, annotation.resource_id)

    %Event{
      id: "annotation-#{annotation.id}",
      type: :highlighted,
      actor_email: email(annotation.user),
      resource_id: annotation.resource_id,
      resource_title: resource && resource.title,
      annotation_id: annotation.id,
      page_number: annotation.page_number,
      snippet: annotation.text,
      inserted_at: annotation.inserted_at
    }
  end

  defp reply_to_event(reply, annotation_lookup, resource_lookup) do
    annotation = Map.get(annotation_lookup, reply.annotation_id)
    resource_id = annotation && annotation.resource_id
    resource = resource_id && Map.get(resource_lookup, resource_id)

    %Event{
      id: "reply-#{reply.id}",
      type: :commented,
      actor_email: email(reply.user),
      resource_id: resource_id,
      resource_title: resource && resource.title,
      annotation_id: reply.annotation_id,
      page_number: annotation && annotation.page_number,
      snippet: reply.body,
      inserted_at: reply.inserted_at
    }
  end

  defp stamp_to_event(stamp, milestone, resource) do
    %Event{
      id: "stamp-#{stamp.id}",
      type: :stamped,
      actor_email: email(stamp.user),
      resource_id: resource.id,
      resource_title: resource.title,
      annotation_id: nil,
      page_number: milestone.page_number,
      snippet: milestone.label,
      inserted_at: stamp.inserted_at
    }
  end

  defp email(%{email: email}) when not is_nil(email), do: to_string(email)
  defp email(_), do: nil
end
