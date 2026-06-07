defmodule Studysync.Library.Resource.Changes.FetchUrl do
  @moduledoc """
  Handles the `:import_from_url` action. Fetches PDF bytes from the provided
  URL server-side (bypassing browser CORS restrictions), validates the
  content-type, stores via the configured Storage adapter, and sets
  `workspace_id`, `title`, `file_path`, and `page_count`.
  """
  use Ash.Resource.Change

  alias Studysync.Library.PdfPageCount
  alias Studysync.Library.Storage

  @impl true
  def change(changeset, _opts, _context) do
    workspace_id = Ash.Changeset.get_argument(changeset, :workspace_id)
    title = Ash.Changeset.get_argument(changeset, :title)
    url = Ash.Changeset.get_argument(changeset, :url)

    Ash.Changeset.before_action(changeset, fn changeset ->
      with {:ok, content} <- fetch_pdf(url),
           key = build_key(workspace_id),
           {:ok, ^key} <- Storage.put(content, key) do
        page_count = PdfPageCount.count(content)

        changeset
        |> Ash.Changeset.force_change_attribute(:workspace_id, workspace_id)
        |> Ash.Changeset.force_change_attribute(:title, title)
        |> Ash.Changeset.force_change_attribute(:file_path, key)
        |> Ash.Changeset.force_change_attribute(:page_count, page_count)
      else
        {:error, reason} ->
          Ash.Changeset.add_error(changeset, field: :url, message: reason)
      end
    end)
  end

  defp fetch_pdf(url) do
    case Req.get(url, redirect: true, receive_timeout: 30_000) do
      {:ok, %{status: 200, headers: headers, body: body}} ->
        content_type = get_content_type(headers)

        if pdf_content_type?(content_type) or pdf_body?(body) do
          {:ok, body}
        else
          {:error, "URL did not return a PDF (content-type: #{content_type})"}
        end

      {:ok, %{status: status}} ->
        {:error, "URL returned HTTP #{status}"}

      {:error, exception} ->
        {:error, "Could not fetch URL: #{Exception.message(exception)}"}
    end
  end

  defp get_content_type(headers) do
    headers
    |> Map.get("content-type", [""])
    |> List.first()
    |> String.downcase()
  end

  defp pdf_content_type?(ct), do: String.contains?(ct, "pdf")

  # Some servers (arxiv) serve with octet-stream; trust the PDF magic bytes.
  defp pdf_body?(<<"%PDF", _::binary>>), do: true
  defp pdf_body?(_), do: false

  defp build_key(workspace_id) do
    "resources/#{workspace_id}/#{Ash.UUID.generate()}.pdf"
  end
end
