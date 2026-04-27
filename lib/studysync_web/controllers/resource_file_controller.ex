defmodule StudysyncWeb.ResourceFileController do
  @moduledoc """
  Streams a Library.Resource's PDF bytes — gated by the resource's read
  policy so only active workspace members can fetch the file. The PDF.js
  reader in `PdfCanvasRenderer` fetches via this route.
  """
  use StudysyncWeb, :controller

  alias Studysync.Library
  alias Studysync.Library.Storage

  def show(conn, %{"id" => id}) do
    actor = conn.assigns[:current_user]

    case Library.get_resource(id, actor: actor) do
      {:ok, resource} when not is_nil(resource) ->
        case Storage.read(resource.file_path) do
          {:ok, bytes} ->
            conn
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(inline; filename="#{Path.basename(resource.file_path)}")
            )
            |> send_resp(200, bytes)

          {:error, _reason} ->
            send_resp(conn, 404, "")
        end

      _ ->
        send_resp(conn, 404, "")
    end
  end
end
