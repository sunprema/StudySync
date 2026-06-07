defmodule Studysync.AI.AnswerWorker do
  @moduledoc """
  Oban worker for Slice 11 — AI assistant.

  Receives an `annotation_id`, loads the annotation + its thread, builds a
  reading-companion prompt, calls the AI, and writes the response back as an
  `AnnotationComment` with `is_ai_response: true`. The `BroadcastReply`
  after-action change then fans the `:reply_created` PubSub event out to all
  open readers, so the AI response appears in the thread without a page
  refresh.

  If the AI call fails after all retries, a graceful error comment is written
  so the user always sees feedback.
  """

  use Oban.Worker, queue: :ai, max_attempts: 3

  require Ash.Query

  alias Studysync.AI.Client
  alias Studysync.Annotations
  alias Studysync.Annotations.Annotation
  alias Studysync.Annotations.AnnotationComment

  @max_reply_context 5

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"annotation_id" => annotation_id},
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    with {:ok, annotation} <- fetch_annotation(annotation_id),
         prompt = build_prompt(annotation),
         {:ok, answer} <- call_ai(prompt),
         {:ok, _reply} <- write_reply(annotation_id, answer) do
      :ok
    else
      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        if attempt >= max_attempts do
          _ = write_error_reply(annotation_id)
          :ok
        else
          {:error, reason}
        end
    end
  end

  defp fetch_annotation(annotation_id) do
    case Ash.get(Annotation, annotation_id,
           authorize?: false,
           load: [replies: Ash.Query.sort(AnnotationComment, inserted_at: :asc)]
         ) do
      {:ok, annotation} ->
        {:ok, annotation}

      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_prompt(annotation) do
    type_label =
      case annotation.type do
        :question -> "question"
        :puzzle -> "puzzle"
        _ -> "note"
      end

    passage =
      if annotation.text && annotation.text != "",
        do: "\n\nHighlighted passage:\n\"#{annotation.text}\"",
        else: ""

    body_line =
      if annotation.body && annotation.body != "",
        do: "\n\nTheir #{type_label}: #{annotation.body}",
        else: "\n\nThe reader selected this passage without adding a note."

    thread_context =
      annotation.replies
      |> Enum.take(-@max_reply_context)
      |> case do
        [] ->
          ""

        replies ->
          lines =
            Enum.map_join(replies, "\n", fn r ->
              if r.is_ai_response, do: "AI: #{r.body}", else: "Reader: #{r.body}"
            end)

          "\n\nPrior thread:\n#{lines}"
      end

    """
    You are a thoughtful reading companion helping a reader engage with a book passage.

    Page #{annotation.page_number}#{passage}#{body_line}#{thread_context}

    Respond helpfully and directly in 2–4 sentences. If they asked a question, answer it; \
    if they flagged a puzzle, help unlock it; if they left a comment, engage with the idea. \
    Write in second person ("You've noticed…", "This passage…"). Be warm but precise. \
    No bullet points.
    """
  end

  defp call_ai(prompt) do
    complete_fn = Application.get_env(:studysync, :ai_complete_fn, &Client.complete/2)
    complete_fn.(prompt, max_tokens: 400)
  end

  defp write_reply(annotation_id, body) do
    Annotations.ai_reply(annotation_id, body, authorize?: false)
  end

  defp write_error_reply(annotation_id) do
    Annotations.ai_reply(
      annotation_id,
      "I wasn't able to respond to this passage right now. Please try again.",
      authorize?: false
    )
  end
end
