defmodule Studysync.SprintsTest do
  use Studysync.DataCase, async: true
  use Oban.Testing, repo: Studysync.Repo

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Annotations
  alias Studysync.Library
  alias Studysync.Library.Storage
  alias Studysync.Sprints
  alias Studysync.Sprints.ExpireJob
  alias Studysync.Sprints.Sprint
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

  defp setup_workspace(owner_email) do
    owner = register_user(owner_email)
    workspace = Workspaces.create_workspace!("Reading Group", actor: owner)

    resource =
      Library.upload_resource!(
        workspace.id,
        "Test Book",
        %{content: @minimal_pdf, filename: "book.pdf"},
        actor: owner
      )

    on_exit(fn -> Storage.delete(resource.file_path) end)
    {owner, workspace, resource}
  end

  defp join_workspace(workspace, owner, email) do
    member = register_user(email)
    Workspaces.invite_member!(workspace.id, email, actor: owner)

    [pending] =
      Studysync.Workspaces.Membership
      |> Ash.Query.filter(workspace_id == ^workspace.id and user_id == ^member.id)
      |> Ash.read!(authorize?: false)

    Workspaces.accept_invite!(pending, actor: member)
    member
  end

  describe "start_sprint/6" do
    test "an active workspace member can start a sprint" do
      {owner, workspace, resource} = setup_workspace("sprint-start@example.com")

      assert {:ok, sprint} =
               Sprints.start_sprint(resource.id, workspace.id, 1, 10, 15, actor: owner)

      assert sprint.status == :active
      assert sprint.start_page == 1
      assert sprint.end_page == 10
      assert sprint.duration_minutes == 15
      assert sprint.resource_id == resource.id
    end

    test "starter is automatically a member of the sprint" do
      {owner, workspace, resource} = setup_workspace("sprint-auto-member@example.com")

      {:ok, sprint} = Sprints.start_sprint(resource.id, workspace.id, 1, 5, 10, actor: owner)
      sprint_with_members = Ash.get!(Sprint, sprint.id, load: [:members], authorize?: false)

      assert Enum.any?(sprint_with_members.members, &(&1.user_id == owner.id))
    end

    test "broadcasts :sprint_started on the resource topic" do
      {owner, workspace, resource} = setup_workspace("sprint-bc@example.com")
      Phoenix.PubSub.subscribe(Studysync.PubSub, "resource:#{resource.id}")

      {:ok, sprint} = Sprints.start_sprint(resource.id, workspace.id, 2, 8, 5, actor: owner)

      assert_receive {:sprint_started, %Sprint{id: id}}, 2000
      assert id == sprint.id
    end

    test "non-member cannot start a sprint" do
      {_owner, workspace, resource} = setup_workspace("sprint-policy@example.com")
      stranger = register_user("sprint-stranger@example.com")

      assert {:error, _} =
               Sprints.start_sprint(resource.id, workspace.id, 1, 5, 10, actor: stranger)
    end
  end

  describe "join_sprint/2" do
    test "an active member can join a sprint" do
      {owner, workspace, resource} = setup_workspace("sprint-join@example.com")
      peer = join_workspace(workspace, owner, "sprint-join-peer@example.com")

      {:ok, sprint} = Sprints.start_sprint(resource.id, workspace.id, 1, 10, 15, actor: owner)

      assert {:ok, _member} = Sprints.join_sprint(sprint.id, actor: peer)
      assert Sprints.sprint_member?(sprint, peer.id)
    end

    test "broadcasts :sprint_joined after joining" do
      {owner, workspace, resource} = setup_workspace("sprint-join-bc@example.com")
      peer = join_workspace(workspace, owner, "sprint-join-bc-peer@example.com")

      {:ok, sprint} = Sprints.start_sprint(resource.id, workspace.id, 1, 5, 10, actor: owner)
      Phoenix.PubSub.subscribe(Studysync.PubSub, "resource:#{resource.id}")

      {:ok, _} = Sprints.join_sprint(sprint.id, actor: peer)

      assert_receive {:sprint_joined, %Sprint{}}, 2000
    end
  end

  describe "ExpireJob" do
    test "transitions sprint to :ended and broadcasts :sprint_ended" do
      {owner, workspace, resource} = setup_workspace("sprint-expire@example.com")

      {:ok, sprint} = Sprints.start_sprint(resource.id, workspace.id, 1, 5, 1, actor: owner)
      Phoenix.PubSub.subscribe(Studysync.PubSub, "resource:#{resource.id}")

      assert :ok =
               perform_job(ExpireJob, %{
                 "sprint_id" => sprint.id,
                 "resource_id" => resource.id
               })

      ended = Ash.get!(Sprint, sprint.id, authorize?: false)
      assert ended.status == :ended
      assert ended.ended_at != nil

      assert_receive {:sprint_ended, %Sprint{status: :ended}}, 2000
    end

    test "is idempotent when sprint is already ended" do
      {owner, workspace, resource} = setup_workspace("sprint-idempotent@example.com")

      {:ok, sprint} = Sprints.start_sprint(resource.id, workspace.id, 1, 5, 1, actor: owner)

      assert :ok =
               perform_job(ExpireJob, %{
                 "sprint_id" => sprint.id,
                 "resource_id" => resource.id
               })

      assert :ok =
               perform_job(ExpireJob, %{
                 "sprint_id" => sprint.id,
                 "resource_id" => resource.id
               })
    end
  end

  describe "compare_notes/1" do
    test "returns only annotations within the sprint window and page range by members" do
      {owner, workspace, resource} = setup_workspace("sprint-compare@example.com")
      peer = join_workspace(workspace, owner, "sprint-compare-peer@example.com")

      {:ok, sprint} = Sprints.start_sprint(resource.id, workspace.id, 2, 5, 15, actor: owner)
      Sprints.join_sprint(sprint.id, actor: peer)

      # Inside sprint range
      Annotations.create_comment!(resource.id, 3, @rect, "text", "owner note", actor: owner)
      Annotations.create_comment!(resource.id, 4, @rect, "text", "peer note", actor: peer)

      # Outside page range — should be excluded
      Annotations.create_comment!(resource.id, 1, @rect, "text", "wrong page", actor: owner)

      sprint_with_members =
        Ash.get!(Sprint, sprint.id, load: [:members], authorize?: false)

      # Use a far-future ended_at to avoid Postgres/Elixir clock-skew in sandbox.
      ended_sprint = %{
        sprint_with_members
        | ended_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      notes = Sprints.compare_notes(ended_sprint)

      all_bodies =
        notes
        |> Enum.flat_map(fn {_uid, _email, anns} -> Enum.map(anns, & &1.body) end)

      assert "owner note" in all_bodies
      assert "peer note" in all_bodies
      refute "wrong page" in all_bodies
    end

    test "returns an entry per member" do
      {owner, workspace, resource} = setup_workspace("sprint-members@example.com")
      peer = join_workspace(workspace, owner, "sprint-members-peer@example.com")

      {:ok, sprint} = Sprints.start_sprint(resource.id, workspace.id, 1, 10, 15, actor: owner)
      Sprints.join_sprint(sprint.id, actor: peer)

      Annotations.create_comment!(resource.id, 2, @rect, "text", "note", actor: owner)
      Annotations.create_comment!(resource.id, 3, @rect, "text", "note", actor: peer)

      sprint_with_members =
        Ash.get!(Sprint, sprint.id, load: [:members], authorize?: false)

      ended_sprint = %{
        sprint_with_members
        | ended_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      notes = Sprints.compare_notes(ended_sprint)

      assert length(notes) == 2
    end
  end
end
