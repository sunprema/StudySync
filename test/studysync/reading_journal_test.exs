defmodule Studysync.ReadingJournalTest do
  use Studysync.DataCase, async: true

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Annotations
  alias Studysync.Library
  alias Studysync.Library.Storage
  alias Studysync.ReadingJournal
  alias Studysync.Workspaces

  @minimal_pdf """
  %PDF-1.4
  1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
  2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
  3 0 obj << /Type /Page /Parent 2 0 R >> endobj
  trailer << /Root 1 0 R >>
  %%EOF
  """

  @rect %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05}

  defp register_user(email) do
    Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: email,
      password: "password1234",
      password_confirmation: "password1234"
    })
    |> Ash.create!(authorize?: false)
  end

  defp setup_resource(owner) do
    workspace = Workspaces.create_workspace!("Reading Group", actor: owner)

    resource =
      Library.upload_resource!(
        workspace.id,
        "Invisible Cities",
        %{content: @minimal_pdf, filename: "calvino.pdf"},
        actor: owner
      )

    on_exit(fn -> Storage.delete(resource.file_path) end)
    {workspace, resource}
  end

  defp add_comment(actor, resource, page, body) do
    Annotations.create_comment!(
      resource.id,
      page,
      @rect,
      "some highlighted text",
      body,
      actor: actor
    )
  end

  describe "build_data/2" do
    test "returns book title, reader email, and annotation count" do
      owner = register_user("owner@example.com")
      {_ws, resource} = setup_resource(owner)

      add_comment(owner, resource, 1, "first thought")
      add_comment(owner, resource, 3, "later thought")

      assert {:ok, data} = ReadingJournal.build_data(owner, resource.id)
      assert data.book_title == "Invisible Cities"
      assert data.reader_email == "owner@example.com"
      assert data.annotation_count == 2
    end

    test "groups annotations by page in ascending order" do
      owner = register_user("owner2@example.com")
      {_ws, resource} = setup_resource(owner)

      add_comment(owner, resource, 5, "page five note")
      add_comment(owner, resource, 2, "page two note")
      add_comment(owner, resource, 2, "another page two note")

      assert {:ok, data} = ReadingJournal.build_data(owner, resource.id)
      pages = data.pages
      assert length(pages) == 2
      [first, second] = pages
      assert first.page_number == 2
      assert length(first.annotations) == 2
      assert second.page_number == 5
      assert length(second.annotations) == 1
    end

    test "only includes the actor's own annotations, not other members'" do
      owner = register_user("owner3@example.com")
      peer = register_user("peer@example.com")
      {workspace, resource} = setup_resource(owner)

      Workspaces.invite_member!(workspace.id, "peer@example.com", actor: owner)

      [pending] =
        Studysync.Workspaces.Membership
        |> Ash.Query.filter(workspace_id == ^workspace.id and user_id == ^peer.id)
        |> Ash.read!(authorize?: false)

      Workspaces.accept_invite!(pending, actor: peer)

      add_comment(owner, resource, 1, "owner note")
      add_comment(peer, resource, 1, "peer note")

      assert {:ok, data} = ReadingJournal.build_data(owner, resource.id)
      assert data.annotation_count == 1
      [page] = data.pages
      [ann] = page.annotations
      assert ann.body == "owner note"
    end

    test "returns error for non-member" do
      owner = register_user("owner4@example.com")
      stranger = register_user("stranger@example.com")
      {_ws, resource} = setup_resource(owner)

      assert {:error, _} = ReadingJournal.build_data(stranger, resource.id)
    end

    test "serialises annotation type, color, text, and body" do
      owner = register_user("owner5@example.com")
      {_ws, resource} = setup_resource(owner)

      add_comment(owner, resource, 1, "my note")

      assert {:ok, data} = ReadingJournal.build_data(owner, resource.id)
      ann = data.pages |> hd() |> Map.get(:annotations) |> hd()
      assert ann.type == "comment"
      assert ann.color == "peach"
      assert ann.text == "some highlighted text"
      assert ann.body == "my note"
    end

    test "handles resource with no annotations gracefully" do
      owner = register_user("owner6@example.com")
      {_ws, resource} = setup_resource(owner)

      assert {:ok, data} = ReadingJournal.build_data(owner, resource.id)
      assert data.annotation_count == 0
      assert data.pages == []
    end
  end
end
