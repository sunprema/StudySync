defmodule Studysync.AnnotationsTest do
  use Studysync.DataCase, async: true

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Annotations
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

  describe "create_comment" do
    test "an active workspace member can create a workspace-visible comment" do
      {owner, _ws, resource} = setup_resource("create-owner@example.com")

      {:ok, annotation} =
        Annotations.create_comment(
          resource.id,
          1,
          @rect,
          "of cities and signs",
          "what does this passage mean?",
          actor: owner
        )

      assert annotation.type == :comment
      assert annotation.visibility == :workspace
      assert annotation.user_id == owner.id
      assert annotation.text == "of cities and signs"
      assert annotation.body == "what does this passage mean?"
      assert annotation.page_number == 1
      assert annotation.rect == @rect
    end

    test "non-members cannot create" do
      {_owner, _ws, resource} = setup_resource("policy-owner@example.com")
      stranger = register_user("policy-stranger@example.com")

      assert {:error, %Ash.Error.Forbidden{}} =
               Annotations.create_comment(
                 resource.id,
                 1,
                 @rect,
                 "snippet",
                 "thoughts",
                 actor: stranger
               )
    end
  end

  describe "read policies" do
    test "workspace-visible annotations are readable by any active member" do
      {owner, ws, resource} = setup_resource("vis-owner@example.com")
      member = register_user("vis-member@example.com")

      _ = Workspaces.invite_member!(ws.id, "vis-member@example.com", actor: owner)

      [pending] =
        Studysync.Workspaces.Membership
        |> Ash.Query.filter(user_id == ^member.id)
        |> Ash.read!(authorize?: false)

      {:ok, _} = Workspaces.accept_invite(pending, actor: member)

      {:ok, annotation} =
        Annotations.create_comment(
          resource.id,
          1,
          @rect,
          "snippet",
          "shared note",
          actor: owner
        )

      results =
        Annotations.list_annotations!(
          actor: member,
          query: [filter: [resource_id: resource.id]]
        )

      assert Enum.map(results, & &1.id) == [annotation.id]
    end

    test "private annotations are only visible to the author" do
      {owner, ws, resource} = setup_resource("priv-owner@example.com")
      member = register_user("priv-member@example.com")

      _ = Workspaces.invite_member!(ws.id, "priv-member@example.com", actor: owner)

      [pending] =
        Studysync.Workspaces.Membership
        |> Ash.Query.filter(user_id == ^member.id)
        |> Ash.read!(authorize?: false)

      {:ok, _} = Workspaces.accept_invite(pending, actor: member)

      {:ok, private} =
        Annotations.create_comment(
          resource.id,
          1,
          @rect,
          "secret",
          "for me only",
          %{visibility: :private},
          actor: owner
        )

      assert {:ok, %{id: id}} = Annotations.get_annotation(private.id, actor: owner)
      assert id == private.id

      member_results =
        Annotations.list_annotations!(
          actor: member,
          query: [filter: [resource_id: resource.id]]
        )

      assert member_results == []
    end

    test "non-members cannot read any annotations on the resource" do
      {owner, _ws, resource} = setup_resource("read-owner@example.com")
      stranger = register_user("read-stranger@example.com")

      {:ok, _} =
        Annotations.create_comment(
          resource.id,
          1,
          @rect,
          "x",
          "y",
          actor: owner
        )

      results =
        Annotations.list_annotations!(
          actor: stranger,
          query: [filter: [resource_id: resource.id]]
        )

      assert results == []
    end
  end

  describe "reply (annotation threads)" do
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

    test "a workspace member can reply to a workspace-visible annotation" do
      {owner, ws, resource} = setup_resource("reply-owner@example.com")
      member = accept_member(ws, owner, "reply-member@example.com")

      {:ok, annotation} =
        Annotations.create_comment(
          resource.id,
          1,
          @rect,
          "of cities and signs",
          "what does this passage mean?",
          actor: owner
        )

      {:ok, reply} = Annotations.reply(annotation.id, "I think it's about memory.", actor: member)

      assert reply.body == "I think it's about memory."
      assert reply.is_ai_response == false
      assert reply.user_id == member.id
      assert reply.annotation_id == annotation.id
    end

    test "non-members cannot reply to a workspace-visible annotation" do
      {owner, _ws, resource} = setup_resource("reply-policy-owner@example.com")
      stranger = register_user("reply-policy-stranger@example.com")

      {:ok, annotation} =
        Annotations.create_comment(resource.id, 1, @rect, "snippet", "body", actor: owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               Annotations.reply(annotation.id, "intruder thoughts", actor: stranger)
    end

    test "non-author members cannot reply to a private annotation" do
      {owner, ws, resource} = setup_resource("priv-thread-owner@example.com")
      member = accept_member(ws, owner, "priv-thread-member@example.com")

      {:ok, private} =
        Annotations.create_comment(
          resource.id,
          1,
          @rect,
          "secret",
          "for me only",
          %{visibility: :private},
          actor: owner
        )

      assert {:error, %Ash.Error.Forbidden{}} =
               Annotations.reply(private.id, "snooping", actor: member)

      assert {:ok, _} = Annotations.reply(private.id, "self-note", actor: owner)
    end

    test "replies are visible to workspace members and reply_count aggregate is correct" do
      {owner, ws, resource} = setup_resource("thread-read-owner@example.com")
      member = accept_member(ws, owner, "thread-read-member@example.com")

      {:ok, annotation} =
        Annotations.create_comment(resource.id, 1, @rect, "snippet", "body", actor: owner)

      {:ok, _} = Annotations.reply(annotation.id, "first reply", actor: owner)
      {:ok, _} = Annotations.reply(annotation.id, "second reply", actor: member)

      replies =
        Annotations.list_replies!(
          actor: member,
          query: [filter: [annotation_id: annotation.id], sort: [inserted_at: :asc]]
        )

      assert length(replies) == 2
      assert Enum.map(replies, & &1.body) == ["first reply", "second reply"]

      [reloaded] =
        Annotations.list_annotations!(
          actor: owner,
          query: [filter: [resource_id: resource.id]],
          load: [:reply_count]
        )

      assert reloaded.reply_count == 2
    end

    test "non-members cannot read replies on a workspace-visible annotation" do
      {owner, _ws, resource} = setup_resource("thread-leak-owner@example.com")
      stranger = register_user("thread-leak-stranger@example.com")

      {:ok, annotation} =
        Annotations.create_comment(resource.id, 1, @rect, "snippet", "body", actor: owner)

      {:ok, _} = Annotations.reply(annotation.id, "members-only", actor: owner)

      results =
        Annotations.list_replies!(
          actor: stranger,
          query: [filter: [annotation_id: annotation.id]]
        )

      assert results == []
    end
  end

  describe "PubSub broadcasts (Slice 7)" do
    # Broadcasts use `broadcast_from!(self())` — the originating process is
    # skipped on purpose so an optimistic-UI insert isn't doubled by the
    # broadcast that the same Ash action emits. To assert receipt we have to
    # subscribe from a *different* process than the one calling the action.
    defp subscribe_from_peer(resource_id) do
      parent = self()
      ref = make_ref()

      pid =
        spawn_link(fn ->
          :ok = Studysync.Annotations.PubSub.subscribe(resource_id)
          send(parent, {ref, :ready})

          receive do
            msg -> send(parent, {ref, :received, msg})
          after
            2_000 -> send(parent, {ref, :timeout})
          end
        end)

      assert_receive {^ref, :ready}, 500
      {ref, pid}
    end

    test "create_comment broadcasts :annotation_created with a minimal payload" do
      {owner, _ws, resource} = setup_resource("broadcast-owner@example.com")
      {ref, _peer} = subscribe_from_peer(resource.id)

      {:ok, annotation} =
        Annotations.create_comment(resource.id, 1, @rect, "snippet", "body", actor: owner)

      assert_receive {^ref, :received, {:annotation_created, payload}}, 500
      # Payload is minimum needed (id + scope) — not a raw Annotation struct
      # (CLAUDE.md §8.4).
      assert payload == %{id: annotation.id, resource_id: resource.id}
    end

    test "the originating process is excluded from its own broadcast" do
      {owner, _ws, resource} = setup_resource("self-skip-owner@example.com")
      :ok = Studysync.Annotations.PubSub.subscribe(resource.id)

      {:ok, _} =
        Annotations.create_comment(resource.id, 1, @rect, "snippet", "body", actor: owner)

      refute_receive {:annotation_created, _}, 200
    end

    test "multiple subscribers all receive a broadcast" do
      {owner, _ws, resource} = setup_resource("multi-sub-owner@example.com")
      {ref_a, _} = subscribe_from_peer(resource.id)
      {ref_b, _} = subscribe_from_peer(resource.id)

      {:ok, annotation} =
        Annotations.create_comment(resource.id, 1, @rect, "snippet", "body", actor: owner)

      assert_receive {^ref_a, :received, {:annotation_created, %{id: id_a}}}, 500
      assert_receive {^ref_b, :received, {:annotation_created, %{id: id_b}}}, 500
      assert id_a == annotation.id
      assert id_b == annotation.id
    end

    test "reply broadcasts :reply_created with id, annotation_id, and resource_id" do
      {owner, _ws, resource} = setup_resource("reply-broadcast-owner@example.com")

      {:ok, annotation} =
        Annotations.create_comment(resource.id, 1, @rect, "snippet", "body", actor: owner)

      {ref, _peer} = subscribe_from_peer(resource.id)

      {:ok, reply} = Annotations.reply(annotation.id, "first reply", actor: owner)

      assert_receive {^ref, :received, {:reply_created, payload}}, 500

      assert payload == %{
               id: reply.id,
               annotation_id: annotation.id,
               resource_id: resource.id
             }
    end
  end
end
