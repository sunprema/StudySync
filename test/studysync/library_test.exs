defmodule Studysync.LibraryTest do
  use Studysync.DataCase, async: true

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Library
  alias Studysync.Library.PdfPageCount
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

  defp build_workspace(actor, name \\ "Reading Group") do
    Workspaces.create_workspace!(name, actor: actor)
  end

  describe "PdfPageCount" do
    test "counts /Type /Page occurrences in a PDF binary, ignoring /Pages" do
      assert PdfPageCount.count(@minimal_pdf) == 3
    end

    test "returns at least 1 even for unparseable input" do
      assert PdfPageCount.count("not a pdf at all") == 1
    end
  end

  describe "Local storage adapter" do
    test "put writes the file under the configured base path and returns the key" do
      key = "resources/test/#{Ash.UUID.generate()}.pdf"
      assert {:ok, ^key} = Storage.put(@minimal_pdf, key)

      base = Application.fetch_env!(:studysync, :storage_path)
      assert File.read!(Path.join(base, key)) == @minimal_pdf

      :ok = Storage.delete(key)
    end

    test "url returns a /uploads/<key> path" do
      assert Storage.url("resources/abc/def.pdf") == "/uploads/resources/abc/def.pdf"
    end

    test "delete is idempotent" do
      assert :ok = Storage.delete("resources/missing/never-stored.pdf")
    end
  end

  describe "upload_resource/3" do
    test "an active workspace member can upload — persists key, page count, uploaded_by" do
      user = register_user("uploader@example.com")
      ws = build_workspace(user)

      resource =
        Library.upload_resource!(
          ws.id,
          "Calvino — Invisible Cities",
          %{content: @minimal_pdf, filename: "calvino.pdf"},
          actor: user
        )

      assert resource.title == "Calvino — Invisible Cities"
      assert resource.workspace_id == ws.id
      assert resource.page_count == 3
      assert resource.uploaded_by_id == user.id
      assert resource.file_path =~ ~r{^resources/#{ws.id}/[\w-]+\.pdf$}

      base = Application.fetch_env!(:studysync, :storage_path)
      assert File.read!(Path.join(base, resource.file_path)) == @minimal_pdf

      :ok = Storage.delete(resource.file_path)
    end

    test "a non-member cannot upload" do
      owner = register_user("owner-up@example.com")
      stranger = register_user("stranger-up@example.com")
      ws = build_workspace(owner)

      assert_raise Ash.Error.Forbidden, fn ->
        Library.upload_resource!(
          ws.id,
          "Forbidden",
          %{content: @minimal_pdf, filename: "f.pdf"},
          actor: stranger
        )
      end
    end
  end

  describe "list_resources" do
    setup do
      user = register_user("lister@example.com")
      ws = build_workspace(user)

      resource =
        Library.upload_resource!(
          ws.id,
          "Borges — Ficciones",
          %{content: @minimal_pdf, filename: "borges.pdf"},
          actor: user
        )

      on_exit(fn -> Storage.delete(resource.file_path) end)

      %{user: user, workspace: ws, resource: resource}
    end

    test "members see their workspace's resources", %{user: user, resource: r} do
      results =
        Library.list_resources!(actor: user, query: [filter: [workspace_id: r.workspace_id]])

      assert Enum.map(results, & &1.id) == [r.id]
    end

    test "non-members see no resources", %{resource: r} do
      stranger = register_user("stranger-list@example.com")

      results =
        Library.list_resources!(actor: stranger, query: [filter: [workspace_id: r.workspace_id]])

      assert results == []
    end
  end

  describe "Slice 9 calculations" do
    @rect %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05}

    defp accept_member(workspace, owner, email) do
      member = register_user(email)
      _ = Studysync.Workspaces.invite_member!(workspace.id, email, actor: owner)

      [pending] =
        Studysync.Workspaces.Membership
        |> Ash.Query.filter(user_id == ^member.id)
        |> Ash.read!(authorize?: false)

      {:ok, _} = Studysync.Workspaces.accept_invite(pending, actor: member)
      member
    end

    setup do
      owner = register_user("calc-owner@example.com")
      ws = Studysync.Workspaces.create_workspace!("Calvino Society", actor: owner)

      resource =
        Library.upload_resource!(
          ws.id,
          "Invisible Cities",
          %{content: @minimal_pdf, filename: "calvino.pdf"},
          actor: owner
        )

      on_exit(fn -> Storage.delete(resource.file_path) end)

      %{owner: owner, workspace: ws, resource: resource}
    end

    test "progress_percent — zero when the user has no annotations", %{
      owner: owner,
      resource: resource
    } do
      [loaded] =
        Library.list_resources!(
          actor: owner,
          query: [filter: [id: resource.id]],
          load: [progress_percent: %{user_id: owner.id}]
        )

      assert loaded.progress_percent == 0
    end

    test "progress_percent — max page / page_count, integer-truncated", %{
      owner: owner,
      resource: resource
    } do
      # page_count is 3 from @minimal_pdf. Annotating page 2 → 2/3 = 66%.
      {:ok, _} =
        Studysync.Annotations.create_comment(
          resource.id,
          1,
          @rect,
          "snippet",
          "body",
          actor: owner
        )

      {:ok, _} =
        Studysync.Annotations.create_comment(
          resource.id,
          2,
          @rect,
          "snippet",
          "body",
          actor: owner
        )

      [loaded] =
        Library.list_resources!(
          actor: owner,
          query: [filter: [id: resource.id]],
          load: [progress_percent: %{user_id: owner.id}]
        )

      assert loaded.progress_percent == 66
    end

    test "progress_percent — only counts the targeted user's annotations", %{
      owner: owner,
      workspace: ws,
      resource: resource
    } do
      member = accept_member(ws, owner, "calc-member@example.com")

      {:ok, _} =
        Studysync.Annotations.create_comment(
          resource.id,
          3,
          @rect,
          "owner-only",
          "body",
          actor: owner
        )

      [for_member] =
        Library.list_resources!(
          actor: member,
          query: [filter: [id: resource.id]],
          load: [progress_percent: %{user_id: member.id}]
        )

      assert for_member.progress_percent == 0
    end

    test "time_spent_seconds — zero with 0 or 1 annotation", %{
      owner: owner,
      resource: resource
    } do
      [loaded_empty] =
        Library.list_resources!(
          actor: owner,
          query: [filter: [id: resource.id]],
          load: [time_spent_seconds: %{user_id: owner.id}]
        )

      assert loaded_empty.time_spent_seconds == 0

      {:ok, _} =
        Studysync.Annotations.create_comment(
          resource.id,
          1,
          @rect,
          "single",
          "body",
          actor: owner
        )

      [loaded_one] =
        Library.list_resources!(
          actor: owner,
          query: [filter: [id: resource.id]],
          load: [time_spent_seconds: %{user_id: owner.id}]
        )

      assert loaded_one.time_spent_seconds == 0
    end

    test "time_spent_seconds — span between earliest and latest annotation", %{
      owner: owner,
      resource: resource
    } do
      {:ok, first} =
        Studysync.Annotations.create_comment(
          resource.id,
          1,
          @rect,
          "first",
          "body",
          actor: owner
        )

      {:ok, second} =
        Studysync.Annotations.create_comment(
          resource.id,
          2,
          @rect,
          "second",
          "body",
          actor: owner
        )

      expected = DateTime.diff(second.inserted_at, first.inserted_at, :second)

      [loaded] =
        Library.list_resources!(
          actor: owner,
          query: [filter: [id: resource.id]],
          load: [time_spent_seconds: %{user_id: owner.id}]
        )

      assert loaded.time_spent_seconds == expected
    end

    test "avg_progress_percent — zero when no annotations exist", %{
      owner: owner,
      resource: resource
    } do
      [loaded] =
        Library.list_resources!(
          actor: owner,
          query: [filter: [id: resource.id]],
          load: [:avg_progress_percent]
        )

      assert loaded.avg_progress_percent == 0
    end

    test "avg_progress_percent — averages max page across annotators", %{
      owner: owner,
      workspace: ws,
      resource: resource
    } do
      member = accept_member(ws, owner, "avg-member@example.com")

      # owner reaches page 3, member reaches page 1.
      # Avg max page = (3 + 1) / 2 = 2 → 2/3 = 66%.
      {:ok, _} =
        Studysync.Annotations.create_comment(resource.id, 3, @rect, "o", "b", actor: owner)

      {:ok, _} =
        Studysync.Annotations.create_comment(resource.id, 1, @rect, "m", "b", actor: member)

      [loaded] =
        Library.list_resources!(
          actor: owner,
          query: [filter: [id: resource.id]],
          load: [:avg_progress_percent]
        )

      assert loaded.avg_progress_percent == 66
    end

    test "avg_progress_percent — non-annotators are not counted as 0%", %{
      owner: owner,
      workspace: ws,
      resource: resource
    } do
      _silent = accept_member(ws, owner, "silent-member@example.com")

      # Only owner has annotated, on page 3 of 3 → 100%.
      # The silent member has zero engagement and shouldn't drag the avg
      # down to 50% — that's reader-card territory, not group pace.
      {:ok, _} =
        Studysync.Annotations.create_comment(resource.id, 3, @rect, "o", "b", actor: owner)

      [loaded] =
        Library.list_resources!(
          actor: owner,
          query: [filter: [id: resource.id]],
          load: [:avg_progress_percent]
        )

      assert loaded.avg_progress_percent == 100
    end
  end
end
