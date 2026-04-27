defmodule StudysyncWeb.PdfLive.ShowTest do
  use StudysyncWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Studysync.Accounts
  alias Studysync.Library
  alias Studysync.Library.Storage
  alias Studysync.Workspaces

  @minimal_pdf """
  %PDF-1.4
  1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
  2 0 obj << /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >> endobj
  3 0 obj << /Type /Page /Parent 2 0 R >> endobj
  4 0 obj << /Type /Page /Parent 2 0 R >> endobj
  5 0 obj << /Type /Page /Parent 2 0 R >> endobj
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

  setup do
    user = register_user("reader@example.com")
    workspace = Workspaces.create_workspace!("Reading Group", actor: user)

    resource =
      Library.upload_resource!(
        workspace.id,
        "Calvino — Invisible Cities",
        %{content: @minimal_pdf, filename: "calvino.pdf"},
        actor: user
      )

    on_exit(fn -> Storage.delete(resource.file_path) end)

    %{user: user, workspace: workspace, resource: resource}
  end

  describe "PdfLive.Show mount + render" do
    test "renders three-column shell with chapter rail, canvas mount, and margin column", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, _view, html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # Three-column shell pieces — assert the structural anchors exist.
      assert html =~ ~s(aria-label="Chapters")
      assert html =~ ~s(id="pdf-canvas")
      assert html =~ "Margin ·"

      # Resource title in the header
      assert html =~ "Calvino"
      # Page count indicator (mono small caps)
      assert html =~ ~r{<span class="num">3</span>\s*pages}
    end

    test "non-members are redirected back to the library", %{
      conn: conn,
      workspace: ws,
      resource: r
    } do
      stranger = register_user("stranger-pdf@example.com")

      assert {:error, {:live_redirect, %{to: target}}} =
               conn
               |> sign_in(stranger)
               |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      assert target == "/workspaces/#{ws.id}/library"
    end

    test "redirects to the library when the resource id does not belong to the workspace in the URL",
         %{conn: conn, user: user, resource: r} do
      other_ws = Workspaces.create_workspace!("Other group", actor: user)

      assert {:error, {:live_redirect, %{to: target}}} =
               conn
               |> sign_in(user)
               |> live(~p"/workspaces/#{other_ws.id}/library/#{r.id}")

      assert target == "/workspaces/#{other_ws.id}/library"
    end
  end

  describe "ResourceFileController" do
    test "members can fetch the PDF bytes", %{conn: conn, user: user, resource: r} do
      conn = conn |> sign_in(user) |> get(~p"/resources/#{r.id}/file")

      assert response(conn, 200) == @minimal_pdf
      assert get_resp_header(conn, "content-type") == ["application/pdf; charset=utf-8"]
    end

    test "non-members get 404", %{conn: conn, resource: r} do
      stranger = register_user("stranger-file@example.com")

      conn = conn |> sign_in(stranger) |> get(~p"/resources/#{r.id}/file")
      assert response(conn, 404)
    end
  end
end
