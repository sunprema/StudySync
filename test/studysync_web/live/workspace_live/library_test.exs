defmodule StudysyncWeb.WorkspaceLive.LibraryTest do
  use StudysyncWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Annotations
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

  describe "Recent activity rail" do
    setup do
      user = register_user("rail-user@example.com")
      ws = Workspaces.create_workspace!("Calvino Society", actor: user)

      resource =
        Library.upload_resource!(
          ws.id,
          "Invisible Cities",
          %{content: @minimal_pdf, filename: "calvino.pdf"},
          actor: user
        )

      on_exit(fn -> Storage.delete(resource.file_path) end)

      %{user: user, workspace: ws, resource: resource}
    end

    test "renders the Recent header with a Live badge", %{conn: conn, user: user, workspace: ws} do
      {:ok, _view, html} = conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library")

      assert html =~ "Recent"
      assert html =~ "Live"
      assert html =~ "Nothing yet"
    end

    test "lists existing annotations as :highlighted activity items", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: resource
    } do
      rect = %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05}

      {:ok, _annotation} =
        Annotations.create_comment(
          resource.id,
          1,
          rect,
          "of cities and signs",
          "what does this mean?",
          actor: user
        )

      {:ok, _view, html} = conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library")

      assert html =~ "highlighted"
      assert html =~ "of cities and signs"
      assert html =~ "rail-user@example.com"
    end
  end

  describe "Slice 9 dashboard" do
    setup do
      owner = register_user("dash-owner@example.com")
      ws = Workspaces.create_workspace!("Calvino Society", actor: owner)

      member = register_user("dash-member@example.com")
      _ = Workspaces.invite_member!(ws.id, "dash-member@example.com", actor: owner)

      [pending] =
        Studysync.Workspaces.Membership
        |> Ash.Query.filter(user_id == ^member.id)
        |> Ash.read!(authorize?: false)

      {:ok, _} = Workspaces.accept_invite(pending, actor: member)

      resource =
        Library.upload_resource!(
          ws.id,
          "Invisible Cities",
          %{content: @minimal_pdf, filename: "calvino.pdf"},
          actor: owner
        )

      on_exit(fn -> Storage.delete(resource.file_path) end)

      %{owner: owner, member: member, workspace: ws, resource: resource}
    end

    test "renders the book title in display serif and the group avg badge", %{
      conn: conn,
      owner: owner,
      workspace: ws,
      resource: resource
    } do
      rect = %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05}

      {:ok, _} =
        Annotations.create_comment(resource.id, 2, rect, "snippet", "body", actor: owner)

      {:ok, _view, html} = conn |> sign_in(owner) |> live(~p"/workspaces/#{ws.id}/library")

      # Book title rendered with the display-serif treatment per the spec.
      assert html =~ ~r{font-display[^"]*">Invisible Cities}
      # Group avg badge — owner reached page 2 of 2 → 100%.
      assert html =~ "Group avg"
      assert html =~ "100%"
      assert html =~ "Open book"
    end

    test "renders a reader card for each active workspace member", %{
      conn: conn,
      owner: owner,
      workspace: ws,
      resource: _resource
    } do
      {:ok, _view, html} = conn |> sign_in(owner) |> live(~p"/workspaces/#{ws.id}/library")

      # Both members appear as reader cards on the dashboard.
      assert html =~ "dash-owner@example.com"
      assert html =~ "dash-member@example.com"
      # Initial state — neither has annotated → both at 0%.
      assert html =~ "Not started"
      # Member roster label — "<span class='num'>2</span> readers".
      assert html =~ ~r{>2</span>\s*\n?\s*readers}
    end

    test "reader cards reflect each member's individual progress", %{
      conn: conn,
      owner: owner,
      member: member,
      workspace: ws,
      resource: resource
    } do
      rect = %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05}

      # Owner reaches page 2 of 2 → 100%; member doesn't annotate → 0%.
      {:ok, _} =
        Annotations.create_comment(resource.id, 2, rect, "snippet", "body", actor: owner)

      {:ok, _view, html} = conn |> sign_in(member) |> live(~p"/workspaces/#{ws.id}/library")

      assert html =~ "Finished"
      assert html =~ "Not started"
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
