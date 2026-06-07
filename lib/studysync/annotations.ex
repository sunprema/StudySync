defmodule Studysync.Annotations do
  use Ash.Domain,
    otp_app: :studysync,
    extensions: [AshPhoenix]

  require Ash.Query

  resources do
    resource Studysync.Annotations.Annotation do
      define :list_annotations, action: :read
      define :get_annotation, action: :read, get_by: [:id]

      define :create_comment,
        action: :create_comment,
        args: [:resource_id, :page_number, :rect, :text, :body]

      define :create_question,
        action: :create_question,
        args: [:resource_id, :page_number, :rect, :text, :body]

      define :create_puzzle,
        action: :create_puzzle,
        args: [:resource_id, :page_number, :rect, :text, :body]
    end

    resource Studysync.Annotations.AnnotationComment do
      define :list_replies, action: :read
      define :reply, action: :reply, args: [:annotation_id, :body]
      define :ai_reply, action: :ai_reply, args: [:annotation_id, :body]
    end
  end

  @doc """
  Lightweight per-resource index of annotations visible to `actor`.

  Slice 15.1: the canvas needs marker geometry for *every* annotation in
  the book — id, type, page, rect, inserted_at, visibility, user_id —
  but the margin column only needs full bodies for the pages currently
  in view. This action returns just the marker-shaped fields, no body /
  text / replies, so the round-trip is cheap even on a 10K-annotation
  book.

  Currently unused by the reader (the margin column eagerly loads full
  annotations after Slice 15a's UX revert), but kept here as a building
  block for future flows that need a cheap whole-book index — and used
  by `priv/scripts/perf_pass.exs` to track index-load latency.
  """
  @spec list_annotation_index(Ash.UUID.t(), keyword()) :: [map()]
  def list_annotation_index(resource_id, opts) when is_binary(resource_id) do
    Studysync.Annotations.Annotation
    |> Ash.Query.filter(resource_id == ^resource_id)
    |> Ash.Query.select([
      :id,
      :type,
      :page_number,
      :rect,
      :inserted_at,
      :user_id,
      :visibility
    ])
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(opts)
  end

  @doc """
  Count annotations on a resource that are visible to `actor`. Uses Ash's
  `count!` so the actor's read policies are honoured. Pass `type:` to
  scope by annotation type.
  """
  @spec count_annotations(Ash.UUID.t(), keyword()) :: non_neg_integer()
  def count_annotations(resource_id, opts) when is_binary(resource_id) do
    {type, opts} = Keyword.pop(opts, :type)

    query =
      Studysync.Annotations.Annotation
      |> Ash.Query.filter(resource_id == ^resource_id)

    query =
      case type do
        nil -> query
        t when is_atom(t) -> Ash.Query.filter(query, type == ^t)
      end

    Ash.count!(query, opts)
  end

  @doc """
  Load full annotations for a single page, for the margin column. Was
  the lazy-load entry point in Slice 15.1; superseded by
  `list_annotations_for_resource/2` after Slice 15a's UX revert (a single
  whole-book load drives a single, stable margin list with a focal-page
  highlight rather than two zones). Kept for the perf script and for
  future flows that need a per-page slice.
  """
  @spec list_annotations_for_pages(Ash.UUID.t(), [pos_integer()], keyword()) :: [map()]
  def list_annotations_for_pages(_resource_id, [], _opts), do: []

  def list_annotations_for_pages(resource_id, pages, opts)
      when is_binary(resource_id) and is_list(pages) do
    Studysync.Annotations.Annotation
    |> Ash.Query.filter(resource_id == ^resource_id)
    |> Ash.Query.filter(page_number in ^pages)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.load([:user, :reply_count])
    |> Ash.read!(opts)
  end

  @doc """
  Load all annotations on a resource visible to `actor`, with `:user` and
  `:reply_count` preloaded — the shape the margin column needs to render
  every card without further round-trips. The reader uses this on mount
  (post Slice 15a revert) so the full-bodied note is always available
  for any peer mark in the book.
  """
  @spec list_annotations_for_resource(Ash.UUID.t(), keyword()) :: [map()]
  def list_annotations_for_resource(resource_id, opts) when is_binary(resource_id) do
    Studysync.Annotations.Annotation
    |> Ash.Query.filter(resource_id == ^resource_id)
    |> Ash.Query.sort([{:page_number, :asc}, {:inserted_at, :asc}])
    |> Ash.Query.load([:user, :reply_count])
    |> Ash.read!(opts)
  end
end
