defmodule Studysync.ReadingJournal do
  @moduledoc """
  Builds the data map for a user's personal reading journal export.

  Reads only the actor's own annotations for a resource (both private and
  workspace-visible ones they authored), orders by page then insertion time,
  and serialises to a flat map that Imprintor can pass to the Typst template.
  """

  require Ash.Query

  alias Studysync.Annotations.Annotation
  alias Studysync.Library

  @doc """
  Builds the template data map for `actor`'s annotations on `resource_id`.

  Returns `{:ok, data}` or `{:error, reason}`.
  """
  def build_data(actor, resource_id) do
    with {:ok, resource} <- fetch_resource(actor, resource_id),
         {:ok, annotations} <- fetch_annotations(actor, resource_id) do
      data = %{
        book_title: resource.title,
        reader_email: to_string(actor.email),
        exported_at: format_date(DateTime.utc_now()),
        annotation_count: length(annotations),
        pages: group_by_page(annotations)
      }

      {:ok, data}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp fetch_resource(actor, resource_id) do
    Library.get_resource(resource_id, actor: actor)
  end

  defp fetch_annotations(actor, resource_id) do
    user_id = actor.id

    Annotation
    |> Ash.Query.filter(resource_id == ^resource_id and user_id == ^user_id)
    |> Ash.Query.sort(page_number: :asc, inserted_at: :asc)
    |> Ash.Query.load(replies: [:user])
    |> Ash.read(actor: actor)
  end

  defp group_by_page(annotations) do
    annotations
    |> Enum.group_by(& &1.page_number)
    |> Enum.sort_by(fn {page, _} -> page end)
    |> Enum.map(fn {page, anns} ->
      %{
        page_number: page,
        annotations: Enum.map(anns, &serialize_annotation/1)
      }
    end)
  end

  defp serialize_annotation(ann) do
    %{
      type: to_string(ann.type),
      color: ann.color || "peach",
      text: ann.text || "",
      body: ann.body || "",
      inserted_at: format_date(ann.inserted_at),
      replies: Enum.map(ann.replies || [], &serialize_reply/1)
    }
  end

  defp serialize_reply(reply) do
    %{
      body: reply.body || "",
      is_ai_response: reply.is_ai_response,
      user_email: reply_author_email(reply),
      inserted_at: format_date(reply.inserted_at)
    }
  end

  defp reply_author_email(%{is_ai_response: true}), do: "AI"
  defp reply_author_email(%{user: %{email: email}}) when not is_nil(email), do: to_string(email)
  defp reply_author_email(_), do: "—"

  defp format_date(nil), do: ""
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%d %b %Y")
  defp format_date(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%d %b %Y")
end
