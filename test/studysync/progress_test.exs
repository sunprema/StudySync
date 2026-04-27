defmodule Studysync.ProgressTest do
  use Studysync.DataCase, async: true

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Library
  alias Studysync.Library.Storage
  alias Studysync.Progress
  alias Studysync.Workspaces

  @minimal_pdf """
  %PDF-1.4
  1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
  2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
  3 0 obj << /Type /Page /Parent 2 0 R >> endobj
  trailer << /Root 1 0 R >>
  %%EOF
  """

  @position %{"x" => 0.5, "y" => 0.25}

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
        "Calvino — Invisible Cities",
        %{content: @minimal_pdf, filename: "calvino.pdf"},
        actor: owner
      )

    on_exit(fn -> Storage.delete(resource.file_path) end)

    {owner, workspace, resource}
  end

  defp accept_member(workspace, owner, email) do
    member = register_user(email)
    _ = Workspaces.invite_member!(workspace.id, email, actor: owner)

    [pending] =
      Studysync.Workspaces.Membership
      |> Ash.Query.filter(user_id == ^member.id)
      |> Ash.read!(authorize?: false)

    {:ok, _} = Workspaces.accept_invite(pending, actor: member)

    member
  end

  describe "create_milestone" do
    test "an active workspace admin can create a milestone" do
      {owner, _ws, resource} = setup_resource("milestone-admin@example.com")

      {:ok, milestone} =
        Progress.create_milestone(
          resource.id,
          1,
          @position,
          "End of Chapter 1",
          actor: owner
        )

      assert milestone.label == "End of Chapter 1"
      assert milestone.page_number == 1
      assert milestone.position == @position
      assert milestone.resource_id == resource.id
      assert milestone.created_by_id == owner.id
    end

    test "non-admin members cannot create milestones" do
      {owner, ws, resource} = setup_resource("non-admin-owner@example.com")
      member = accept_member(ws, owner, "milestone-member@example.com")

      assert {:error, %Ash.Error.Forbidden{}} =
               Progress.create_milestone(
                 resource.id,
                 1,
                 @position,
                 "End of Chapter 1",
                 actor: member
               )
    end

    test "non-members cannot create milestones" do
      {_owner, _ws, resource} = setup_resource("ms-policy-owner@example.com")
      stranger = register_user("ms-policy-stranger@example.com")

      assert {:error, %Ash.Error.Forbidden{}} =
               Progress.create_milestone(
                 resource.id,
                 1,
                 @position,
                 "Stranger milestone",
                 actor: stranger
               )
    end

    test "label is required" do
      {owner, _ws, resource} = setup_resource("ms-blank-label@example.com")

      assert {:error, %Ash.Error.Invalid{}} =
               Progress.create_milestone(resource.id, 1, @position, "", actor: owner)
    end
  end

  describe "apply_stamp" do
    test "an active workspace member can stamp a milestone" do
      {owner, _ws, resource} = setup_resource("stamp-owner@example.com")

      {:ok, milestone} =
        Progress.create_milestone(resource.id, 1, @position, "End of Chapter 1", actor: owner)

      {:ok, stamp} = Progress.apply_stamp(milestone.id, "got there", actor: owner)

      assert stamp.milestone_id == milestone.id
      assert stamp.user_id == owner.id
      assert stamp.note == "got there"
    end

    test "non-members cannot stamp milestones" do
      {owner, _ws, resource} = setup_resource("stamp-policy-owner@example.com")
      stranger = register_user("stamp-policy-stranger@example.com")

      {:ok, milestone} =
        Progress.create_milestone(resource.id, 1, @position, "Hidden", actor: owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               Progress.apply_stamp(milestone.id, nil, actor: stranger)
    end

    test "duplicate stamps for the same user/milestone are rejected" do
      {owner, _ws, resource} = setup_resource("stamp-dup-owner@example.com")

      {:ok, milestone} =
        Progress.create_milestone(resource.id, 1, @position, "Once only", actor: owner)

      {:ok, _} = Progress.apply_stamp(milestone.id, nil, actor: owner)

      assert {:error, %Ash.Error.Invalid{}} =
               Progress.apply_stamp(milestone.id, nil, actor: owner)
    end

    test "two different members can each stamp the same milestone" do
      {owner, ws, resource} = setup_resource("stamp-multi-owner@example.com")
      member = accept_member(ws, owner, "stamp-multi-member@example.com")

      {:ok, milestone} =
        Progress.create_milestone(resource.id, 1, @position, "Group checkpoint", actor: owner)

      {:ok, _} = Progress.apply_stamp(milestone.id, nil, actor: owner)
      {:ok, _} = Progress.apply_stamp(milestone.id, nil, actor: member)

      [%{stamp_count: count}] =
        Progress.list_milestones!(
          actor: owner,
          query: [filter: [resource_id: resource.id], load: [:stamp_count]]
        )

      assert count == 2
    end

    test "stamper_user_ids aggregate returns the list of stampers" do
      {owner, ws, resource} = setup_resource("stamp-list-owner@example.com")
      member = accept_member(ws, owner, "stamp-list-member@example.com")

      {:ok, milestone} =
        Progress.create_milestone(resource.id, 1, @position, "Who stamped?", actor: owner)

      {:ok, _} = Progress.apply_stamp(milestone.id, nil, actor: owner)
      {:ok, _} = Progress.apply_stamp(milestone.id, nil, actor: member)

      [%{stamper_user_ids: ids}] =
        Progress.list_milestones!(
          actor: owner,
          query: [filter: [resource_id: resource.id], load: [:stamper_user_ids]]
        )

      assert Enum.sort(ids) == Enum.sort([owner.id, member.id])
    end

    test "any active workspace member can read stamps in their workspace" do
      {owner, ws, resource} = setup_resource("stamp-read-owner@example.com")
      member = accept_member(ws, owner, "stamp-read-member@example.com")

      {:ok, milestone} =
        Progress.create_milestone(resource.id, 1, @position, "Read me", actor: owner)

      {:ok, _} = Progress.apply_stamp(milestone.id, nil, actor: owner)

      results =
        Progress.list_stamps!(
          actor: member,
          query: [filter: [milestone_id: milestone.id]]
        )

      assert length(results) == 1
    end

    test "non-members cannot read any stamps" do
      {owner, _ws, resource} = setup_resource("stamp-leak-owner@example.com")
      stranger = register_user("stamp-leak-stranger@example.com")

      {:ok, milestone} =
        Progress.create_milestone(resource.id, 1, @position, "Quiet", actor: owner)

      {:ok, _} = Progress.apply_stamp(milestone.id, nil, actor: owner)

      results =
        Progress.list_stamps!(
          actor: stranger,
          query: [filter: [milestone_id: milestone.id]]
        )

      assert results == []
    end
  end

  describe "read policies" do
    test "any active workspace member can read milestones" do
      {owner, ws, resource} = setup_resource("ms-read-owner@example.com")
      member = accept_member(ws, owner, "ms-read-member@example.com")

      {:ok, _} =
        Progress.create_milestone(resource.id, 1, @position, "End of intro", actor: owner)

      results =
        Progress.list_milestones!(
          actor: member,
          query: [filter: [resource_id: resource.id]]
        )

      assert length(results) == 1
      assert hd(results).label == "End of intro"
    end

    test "non-members cannot read any milestones on the resource" do
      {owner, _ws, resource} = setup_resource("ms-leak-owner@example.com")
      stranger = register_user("ms-leak-stranger@example.com")

      {:ok, _} =
        Progress.create_milestone(resource.id, 1, @position, "Hidden", actor: owner)

      results =
        Progress.list_milestones!(
          actor: stranger,
          query: [filter: [resource_id: resource.id]]
        )

      assert results == []
    end
  end
end
