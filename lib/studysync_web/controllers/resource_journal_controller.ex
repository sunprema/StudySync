defmodule StudysyncWeb.ResourceJournalController do
  @moduledoc """
  Generates and streams a user's personal reading journal as a PDF download.
  Only the actor's own annotations are included. Non-members get a 404.
  """
  use StudysyncWeb, :controller

  alias Studysync.ReadingJournal

  # source_document must be the template CONTENT (not a file path) — Imprintor
  # calls Source::detached(source_document) which treats the string as Typst source.
  @template_path Application.app_dir(:studysync, "priv/typst/reading_journal.typ")
  @typst_root Application.app_dir(:studysync, "priv/typst")

  def show(conn, %{"id" => resource_id}) do
    actor = conn.assigns[:current_user]

    case ReadingJournal.build_data(actor, resource_id) do
      {:ok, data} ->
        template_content = File.read!(@template_path)

        config =
          Imprintor.Config.new(
            template_content,
            data,
            root_directory: @typst_root
          )

        case Imprintor.compile_to_pdf(config) do
          {:ok, pdf_bytes} ->
            slug = slugify(data.book_title)

            conn
            |> put_resp_content_type("application/pdf")
            |> put_resp_header(
              "content-disposition",
              ~s(attachment; filename="#{slug}-journal.pdf")
            )
            |> send_resp(200, pdf_bytes)

          {:error, reason} ->
            conn
            |> put_resp_content_type("text/plain")
            |> send_resp(500, "Journal generation failed: #{inspect(reason)}")
        end

      {:error, _} ->
        send_resp(conn, 404, "")
    end
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
