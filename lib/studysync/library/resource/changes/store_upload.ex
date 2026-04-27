defmodule Studysync.Library.Resource.Changes.StoreUpload do
  @moduledoc """
  Translates the `:upload` action's arguments — `workspace_id`, `title`, and
  `upload` (a map with at minimum `:path`) — into persisted attributes:

  * Reads the file at `upload.path`.
  * Computes a page count via `PdfPageCount`.
  * Hands the bytes to the configured `Storage` adapter under a stable key.
  * Sets `workspace_id`, `title`, `file_path` (= storage key), and `page_count`.

  Uploaded_by is set separately by the action's `relate_actor` change.
  """
  use Ash.Resource.Change

  alias Studysync.Library.PdfPageCount
  alias Studysync.Library.Storage

  @impl true
  def change(changeset, _opts, _context) do
    workspace_id = Ash.Changeset.get_argument(changeset, :workspace_id)
    title = Ash.Changeset.get_argument(changeset, :title)
    upload = Ash.Changeset.get_argument(changeset, :upload)

    Ash.Changeset.before_action(changeset, fn changeset ->
      content = read_upload!(upload)
      page_count = PdfPageCount.count(content)
      key = build_key(workspace_id)
      {:ok, ^key} = Storage.put(content, key)

      changeset
      |> Ash.Changeset.force_change_attribute(:workspace_id, workspace_id)
      |> Ash.Changeset.force_change_attribute(:title, title)
      |> Ash.Changeset.force_change_attribute(:file_path, key)
      |> Ash.Changeset.force_change_attribute(:page_count, page_count)
    end)
  end

  defp read_upload!(%{content: content}) when is_binary(content), do: content
  defp read_upload!(%{path: path}) when is_binary(path), do: File.read!(path)

  defp build_key(workspace_id) do
    "resources/#{workspace_id}/#{Ash.UUID.generate()}.pdf"
  end
end
