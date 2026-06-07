defmodule Studysync.AI.CollectiveInsightJob do
  @moduledoc """
  Oban worker that synthesises a "GROUP LENS" collective insight card when
  three or more distinct workspace members have independently annotated the
  same page of a resource.

  Triggered by `TriggerCollectiveInsight` after each successful annotation
  create. The job is idempotent: if an insight already exists for the
  `(resource_id, page_number)` pair it exits immediately, relying on the
  unique DB index to protect against any race between two concurrent jobs.
  """

  use Oban.Worker, queue: :ai, max_attempts: 3

  require Ash.Query

  alias Studysync.AI.Client
  alias Studysync.Annotations.Annotation
  alias Studysync.Progress
  alias Studysync.Progress.CollectiveInsight

  @min_contributors 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_id" => resource_id, "page_number" => page_number}}) do
    with :needs_insight <- check_existing(resource_id, page_number),
         {:ok, annotations} <- fetch_page_annotations(resource_id, page_number),
         {:ok, contributor_ids, annotation_ids} <- check_threshold(annotations),
         {:ok, synthesis} <- synthesise(annotations),
         {:ok, _insight} <-
           create_insight(resource_id, page_number, synthesis, contributor_ids, annotation_ids) do
      :ok
    else
      :already_exists -> :ok
      {:below_threshold, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_existing(resource_id, page_number) do
    CollectiveInsight
    |> Ash.Query.filter(resource_id == ^resource_id and page_number == ^page_number)
    |> Ash.read!(authorize?: false)
    |> case do
      [] -> :needs_insight
      [_ | _] -> :already_exists
    end
  end

  defp fetch_page_annotations(resource_id, page_number) do
    annotations =
      Annotation
      |> Ash.Query.filter(resource_id == ^resource_id and page_number == ^page_number)
      |> Ash.Query.filter(type in [:comment, :question, :puzzle])
      |> Ash.Query.sort(inserted_at: :asc)
      |> Ash.read!(authorize?: false)

    {:ok, annotations}
  end

  defp check_threshold(annotations) do
    contributor_ids =
      annotations
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    annotation_ids = Enum.map(annotations, & &1.id)

    if length(contributor_ids) >= @min_contributors do
      {:ok, contributor_ids, annotation_ids}
    else
      {:below_threshold, length(contributor_ids)}
    end
  end

  defp synthesise(annotations) do
    passages =
      annotations
      |> Enum.map(fn ann ->
        type = ann.type |> Atom.to_string() |> String.upcase()
        passage = if ann.text != "", do: "\n  Passage: \"#{ann.text}\"", else: ""
        "- [#{type}]#{passage}\n  Note: #{ann.body}"
      end)
      |> Enum.join("\n\n")

    prompt = """
    You are helping a reading group understand what they collectively noticed on one page of a book.

    These readers each independently annotated the same page:

    #{passages}

    Write a concise synthesis (2–4 sentences) that identifies the shared themes, tensions, or
    patterns across these annotations. Don't list the annotations back — extract the collective
    insight. Use a thoughtful, literary tone. Write in the third person ("The readers noticed…",
    "A common thread is…"). Do not use bullet points.
    """

    complete_fn = Application.get_env(:studysync, :ai_complete_fn, &Client.complete/2)
    complete_fn.(prompt, max_tokens: 300)
  end

  defp create_insight(resource_id, page_number, synthesis, contributor_ids, annotation_ids) do
    Progress.create_insight(
      resource_id,
      page_number,
      synthesis,
      contributor_ids,
      annotation_ids,
      authorize?: false
    )
  end
end
