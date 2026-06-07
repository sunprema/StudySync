defmodule StudysyncWeb.BoardLive.ShowTest do
  use StudysyncWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Board
  alias Studysync.Library
  alias Studysync.Library.Storage
  alias Studysync.Workspaces

  @minimal_pdf """
  %PDF-1.4
  1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
  2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
  3 0 obj << /Type /Page /Parent 2 0 R >> endobj
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
    user = register_user("board-lv@example.com")
    workspace = Workspaces.create_workspace!("Reading Group", actor: user)

    resource =
      Library.upload_resource!(
        workspace.id,
        "Thinking Fast and Slow",
        %{content: @minimal_pdf, filename: "kahneman.pdf"},
        actor: user
      )

    on_exit(fn -> Storage.delete(resource.file_path) end)

    %{user: user, workspace: workspace, resource: resource}
  end

  describe "Slice 22 — BoardLive.Show" do
    test "mounts with resource title and empty board", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, _view, html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}/board")

      assert html =~ "Thinking Fast and Slow"
      assert html =~ "Board"
    end

    test "redirects to library when resource not found", %{
      conn: conn,
      user: user,
      workspace: ws
    } do
      fake_id = Ash.UUID.generate()

      assert {:error, {:live_redirect, %{to: path}}} =
               conn
               |> sign_in(user)
               |> live(~p"/workspaces/#{ws.id}/library/#{fake_id}/board")

      assert path =~ "/library"
    end

    test "node_created event creates a node in assigns", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}/board")

      render_hook(view, "node_created", %{
        "label" => "System 1",
        "position_x" => 100.0,
        "position_y" => 150.0
      })

      html = render(view)
      assert html =~ "System 1"
    end

    test "node_moved event updates position without reloading unrelated assigns", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, node} = Board.create_node(r.id, "Heuristics", 10.0, 10.0, actor: user)

      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}/board")

      # move_node returns :noreply with no assign change in the originator
      render_hook(view, "node_moved", %{
        "id" => node.id,
        "position_x" => 300.0,
        "position_y" => 400.0
      })

      {:ok, updated} = Board.get_node(node.id, actor: user)
      assert updated.position_x == 300.0
      assert updated.position_y == 400.0
    end

    test "node_deleted event removes a node", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, node} = Board.create_node(r.id, "Priming", 50.0, 50.0, actor: user)

      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}/board")

      render_hook(view, "node_deleted", %{"id" => node.id})

      assert {:ok, []} =
               Ash.read(
                 Ash.Query.filter(Studysync.Board.Node, id == ^node.id),
                 authorize?: false
               )
    end

    test "edge_created event creates an edge", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, a} = Board.create_node(r.id, "Cognitive ease", 0.0, 0.0, actor: user)
      {:ok, b} = Board.create_node(r.id, "Illusion of truth", 200.0, 0.0, actor: user)

      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}/board")

      render_hook(view, "edge_created", %{
        "source_id" => a.id,
        "target_id" => b.id
      })

      edges =
        Ash.read!(
          Ash.Query.filter(Studysync.Board.Edge, resource_id == ^r.id),
          authorize?: false
        )

      assert Enum.any?(edges, &(&1.source_id == a.id and &1.target_id == b.id))
    end

    test "PubSub broadcast from peer updates assigns", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}/board")

      # Simulate a peer creating a node and broadcasting
      {:ok, node} = Board.create_node(r.id, "Availability heuristic", 10.0, 10.0, actor: user)

      send(view.pid, {:node_created, %{id: node.id, resource_id: r.id}})

      html = render(view)
      assert html =~ "Availability heuristic"
    end
  end
end
