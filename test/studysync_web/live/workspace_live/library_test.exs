defmodule StudysyncWeb.WorkspaceLive.LibraryTest do
  use StudysyncWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Studysync.Accounts
  alias Studysync.Library
  alias Studysync.Library.Storage
  alias Studysync.Workspaces

  @minimal_pdf """
  %PDF-1.4
  1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
  2 0 obj << /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >> endobj
  3 0 obj << /Type /Page /Parent 2 0 R >> endobj
  4 0 obj << /Type /Page /Parent 2 0 R >> endobj
  trailer << /Root 1 0 R >>
  %%EOF
  """

  defp register_user(email) do
    Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: email,
      password: "password1234",
      password_confirmation: "password1234"
    })
    |> Ash.create!(authorize?: false)
  end

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  describe "Library mount + render" do
    setup do
      user = register_user("lib-user@example.com")
      ws = Workspaces.create_workspace!("Borges Society", actor: user)
      %{user: user, workspace: ws}
    end

    test "redirects when workspace is not visible", %{conn: conn, workspace: ws} do
      stranger = register_user("stranger-lib@example.com")
      conn = sign_in(conn, stranger)

      assert {:error, {:live_redirect, %{to: "/workspaces"}}} =
               live(conn, ~p"/workspaces/#{ws.id}/library")
    end

    test "renders empty state when no resources exist", %{conn: conn, user: user, workspace: ws} do
      {:ok, _view, html} = conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library")

      assert html =~ "Library"
      assert html =~ "No PDFs yet"
    end

    test "lists existing resources for the workspace", %{conn: conn, user: user, workspace: ws} do
      resource =
        Library.upload_resource!(
          ws.id,
          "Calvino — Invisible Cities",
          %{content: @minimal_pdf, filename: "calvino.pdf"},
          actor: user
        )

      on_exit(fn -> Storage.delete(resource.file_path) end)

      {:ok, _view, html} = conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library")

      assert html =~ "Calvino"
      assert html =~ ~r{>2</span>\s+pages}
    end
  end

  describe "upload form" do
    setup do
      user = register_user("uploader-lv@example.com")
      ws = Workspaces.create_workspace!("Calvino Society", actor: user)
      %{user: user, workspace: ws}
    end

    test "uploading a PDF creates a resource and shows it in the stream", %{
      conn: conn,
      user: user,
      workspace: ws
    } do
      {:ok, view, _html} = conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library")

      # Set the title via phx-change.
      view
      |> element("#upload-form")
      |> render_change(%{"title" => "Borges — Ficciones"})

      # Stage the file through the live_file_input.
      file =
        file_input(view, "#upload-form", :pdf, [
          %{
            name: "ficciones.pdf",
            content: @minimal_pdf,
            type: "application/pdf"
          }
        ])

      assert render_upload(file, "ficciones.pdf") =~ ~r{progress}

      view
      |> element("#upload-form")
      |> render_submit(%{"title" => "Borges — Ficciones"})

      results =
        Library.list_resources!(
          actor: user,
          query: [filter: [workspace_id: ws.id]]
        )

      assert [resource] = results
      assert resource.title == "Borges — Ficciones"
      assert resource.page_count == 2

      on_exit(fn -> Storage.delete(resource.file_path) end)
    end
  end
end
