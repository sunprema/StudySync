defmodule Studysync.BoardTest do
  use Studysync.DataCase, async: true

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

  defp setup_resource(owner_email) do
    owner = register_user(owner_email)
    workspace = Workspaces.create_workspace!("Reading Group", actor: owner)

    resource =
      Library.upload_resource!(
        workspace.id,
        "Thinking Fast and Slow",
        %{content: @minimal_pdf, filename: "kahneman.pdf"},
        actor: owner
      )

    on_exit(fn -> Storage.delete(resource.file_path) end)

    {owner, workspace, resource}
  end

  describe "create_node" do
    test "an active workspace member can create a node" do
      {owner, _ws, resource} = setup_resource("board-create@example.com")

      {:ok, node} = Board.create_node(resource.id, "System 1", 100.0, 150.0, actor: owner)

      assert node.label == "System 1"
      assert node.position_x == 100.0
      assert node.position_y == 150.0
      assert node.resource_id == resource.id
      assert node.user_id == owner.id
    end

    test "non-member cannot create a node" do
      {_owner, _ws, resource} = setup_resource("board-owner@example.com")
      stranger = register_user("board-stranger@example.com")

      assert {:error, _} = Board.create_node(resource.id, "Intruder", 0.0, 0.0, actor: stranger)
    end

    test "color defaults to 'default' when not set" do
      {owner, _ws, resource} = setup_resource("board-color@example.com")

      {:ok, node} = Board.create_node(resource.id, "Dual process", 50.0, 50.0, actor: owner)

      assert node.color == "default"
    end
  end

  describe "move_node" do
    test "a member can move a node to a new position" do
      {owner, _ws, resource} = setup_resource("board-move@example.com")

      {:ok, node} = Board.create_node(resource.id, "Heuristics", 10.0, 20.0, actor: owner)
      {:ok, moved} = Board.move_node(node, 300.0, 400.0, actor: owner)

      assert moved.position_x == 300.0
      assert moved.position_y == 400.0
    end
  end

  describe "delete_node" do
    test "a member can delete a node" do
      {owner, _ws, resource} = setup_resource("board-delete@example.com")

      {:ok, node} = Board.create_node(resource.id, "Anchoring", 10.0, 10.0, actor: owner)
      :ok = Board.delete_node(node, actor: owner)

      assert {:ok, []} =
               Ash.read(
                 Ash.Query.filter(Studysync.Board.Node, id == ^node.id),
                 authorize?: false
               )
    end

    test "deleting a node cascades to its edges" do
      {owner, _ws, resource} = setup_resource("board-cascade@example.com")

      {:ok, a} = Board.create_node(resource.id, "Bias", 10.0, 10.0, actor: owner)
      {:ok, b} = Board.create_node(resource.id, "Error", 100.0, 100.0, actor: owner)
      {:ok, edge} = Board.create_edge(resource.id, a.id, b.id, actor: owner)
      :ok = Board.delete_node(a, actor: owner)

      assert {:ok, []} =
               Ash.read(
                 Ash.Query.filter(Studysync.Board.Edge, id == ^edge.id),
                 authorize?: false
               )
    end
  end

  describe "create_edge" do
    test "a member can connect two nodes" do
      {owner, _ws, resource} = setup_resource("board-edge@example.com")

      {:ok, a} = Board.create_node(resource.id, "Thinking", 0.0, 0.0, actor: owner)
      {:ok, b} = Board.create_node(resource.id, "Deciding", 200.0, 0.0, actor: owner)

      {:ok, edge} = Board.create_edge(resource.id, a.id, b.id, actor: owner)

      assert edge.source_id == a.id
      assert edge.target_id == b.id
    end

    test "duplicate edge is rejected" do
      {owner, _ws, resource} = setup_resource("board-dup@example.com")

      {:ok, a} = Board.create_node(resource.id, "A", 0.0, 0.0, actor: owner)
      {:ok, b} = Board.create_node(resource.id, "B", 100.0, 0.0, actor: owner)
      {:ok, _} = Board.create_edge(resource.id, a.id, b.id, actor: owner)

      assert {:error, _} = Board.create_edge(resource.id, a.id, b.id, actor: owner)
    end
  end

  describe "delete_edge" do
    test "a member can delete an edge" do
      {owner, _ws, resource} = setup_resource("board-del-edge@example.com")

      {:ok, a} = Board.create_node(resource.id, "X", 0.0, 0.0, actor: owner)
      {:ok, b} = Board.create_node(resource.id, "Y", 100.0, 0.0, actor: owner)
      {:ok, edge} = Board.create_edge(resource.id, a.id, b.id, actor: owner)

      :ok = Board.delete_edge(edge, actor: owner)

      assert {:ok, []} =
               Ash.read(
                 Ash.Query.filter(Studysync.Board.Edge, id == ^edge.id),
                 authorize?: false
               )
    end
  end
end
