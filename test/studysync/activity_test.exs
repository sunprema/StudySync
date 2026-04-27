defmodule Studysync.ActivityTest do
  use Studysync.DataCase, async: true

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Activity
  alias Studysync.Activity.PubSub, as: ActivityPubSub
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

  defp setup_workspace(owner_email) do
    owner = register_user(owner_email)
    workspace = Workspaces.create_workspace!("Reading Group", actor: owner)
    {owner, workspace}
  end

  defp upload_resource(workspace, owner, title) do
    resource =
      Library.upload_resource!(
        workspace.id,
        title,
        %{content: @minimal_pdf, filename: "calvino.pdf"},
        actor: owner
      )

    on_exit(fn -> Storage.delete(resource.file_path) end)
    resource
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

  describe "list_for_workspace/2" do
    test "returns an empty list when the workspace has no resources" do
      {owner, workspace} = setup_workspace("empty-ws@example.com")

      assert Activity.list_for_workspace(workspace.id, actor: owner) == []
    end

    test "surfaces annotations as :highlighted events newest-first" do
      {owner, workspace} = setup_workspace("annotated-ws@example.com")
      resource = upload_resource(workspace, owner, "Calvino")

      {:ok, first} =
        Annotations.create_comment(resource.id, 1, @rect, "snippet one", "body", actor: owner)

      {:ok, second} =
        Annotations.create_comment(resource.id, 2, @rect, "snippet two", "body", actor: owner)

      events = Activity.list_for_workspace(workspace.id, actor: owner)

      assert [
               %{type: :highlighted, snippet: "snippet two"},
               %{type: :highlighted, snippet: "snippet one"}
             ] = events

      assert Enum.map(events, & &1.id) == ["annotation-#{second.id}", "annotation-#{first.id}"]
      assert Enum.all?(events, &(&1.resource_title == "Calvino"))
      assert Enum.all?(events, &(&1.actor_email == "annotated-ws@example.com"))
    end

    test "surfaces replies as :commented events alongside annotations, sorted by time" do
      {owner, workspace} = setup_workspace("threaded-ws@example.com")
      resource = upload_resource(workspace, owner, "Calvino")

      {:ok, annotation} =
        Annotations.create_comment(resource.id, 1, @rect, "highlight", "first", actor: owner)

      {:ok, reply} =
        Annotations.reply(annotation.id, "a reply body", actor: owner)

      events = Activity.list_for_workspace(workspace.id, actor: owner)

      assert [first | _] = events
      assert first.type == :commented
      assert first.id == "reply-#{reply.id}"
      assert first.snippet == "a reply body"
      assert first.page_number == 1

      assert Enum.any?(
               events,
               &(&1.type == :highlighted and &1.id == "annotation-#{annotation.id}")
             )
    end

    test "honours read policies — non-members see nothing" do
      {owner, workspace} = setup_workspace("policy-ws@example.com")
      resource = upload_resource(workspace, owner, "Calvino")
      stranger = register_user("policy-stranger@example.com")

      {:ok, _} =
        Annotations.create_comment(resource.id, 1, @rect, "snip", "body", actor: owner)

      assert Activity.list_for_workspace(workspace.id, actor: stranger) == []
    end

    test "private annotations are filtered out for other members" do
      {owner, workspace} = setup_workspace("private-ws@example.com")
      resource = upload_resource(workspace, owner, "Calvino")
      member = accept_member(workspace, owner, "private-member@example.com")

      {:ok, _public} =
        Annotations.create_comment(resource.id, 1, @rect, "shared snip", "body", actor: owner)

      {:ok, _private} =
        Annotations.create_comment(
          resource.id,
          2,
          @rect,
          "secret snip",
          "body",
          %{visibility: :private},
          actor: owner
        )

      member_events = Activity.list_for_workspace(workspace.id, actor: member)
      assert Enum.map(member_events, & &1.snippet) == ["shared snip"]

      owner_snippets =
        workspace.id
        |> Activity.list_for_workspace(actor: owner)
        |> Enum.map(& &1.snippet)

      assert Enum.sort(owner_snippets) == ["secret snip", "shared snip"]
    end

    test "respects the :limit option" do
      {owner, workspace} = setup_workspace("limited-ws@example.com")
      resource = upload_resource(workspace, owner, "Calvino")

      for i <- 1..5 do
        {:ok, _} =
          Annotations.create_comment(
            resource.id,
            1,
            @rect,
            "snip #{i}",
            "body",
            actor: owner
          )
      end

      events = Activity.list_for_workspace(workspace.id, actor: owner, limit: 3)
      assert length(events) == 3
    end
  end

  describe "event_from_annotation/2" do
    test "returns an event for a visible annotation" do
      {owner, workspace} = setup_workspace("event-anno-ws@example.com")
      resource = upload_resource(workspace, owner, "Calvino")

      {:ok, annotation} =
        Annotations.create_comment(resource.id, 3, @rect, "shown", "body", actor: owner)

      assert {:ok, event} = Activity.event_from_annotation(annotation.id, actor: owner)
      assert event.type == :highlighted
      assert event.id == "annotation-#{annotation.id}"
      assert event.page_number == 3
      assert event.snippet == "shown"
    end

    test "returns :not_visible when the actor cannot read the annotation" do
      {owner, workspace} = setup_workspace("event-anno-priv-ws@example.com")
      resource = upload_resource(workspace, owner, "Calvino")
      stranger = register_user("event-anno-stranger@example.com")

      {:ok, annotation} =
        Annotations.create_comment(resource.id, 1, @rect, "snip", "body", actor: owner)

      assert {:error, :not_visible} =
               Activity.event_from_annotation(annotation.id, actor: stranger)
    end
  end

  describe "event_from_reply/2" do
    test "returns an event for a visible reply with the parent's page number" do
      {owner, workspace} = setup_workspace("event-reply-ws@example.com")
      resource = upload_resource(workspace, owner, "Calvino")

      {:ok, annotation} =
        Annotations.create_comment(resource.id, 4, @rect, "passage", "body", actor: owner)

      {:ok, reply} = Annotations.reply(annotation.id, "second take", actor: owner)

      assert {:ok, event} = Activity.event_from_reply(reply.id, actor: owner)
      assert event.type == :commented
      assert event.id == "reply-#{reply.id}"
      assert event.page_number == 4
      assert event.snippet == "second take"
    end
  end

  describe "PubSub workspace topic" do
    defp subscribe_from_peer(workspace_id) do
      parent = self()
      ref = make_ref()

      pid =
        spawn_link(fn ->
          :ok = ActivityPubSub.subscribe(workspace_id)
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

    test "annotation creation broadcasts :activity_annotation_created on the workspace topic" do
      {owner, workspace} = setup_workspace("ws-pubsub-anno@example.com")
      resource = upload_resource(workspace, owner, "Calvino")
      {ref, _peer} = subscribe_from_peer(workspace.id)

      {:ok, annotation} =
        Annotations.create_comment(resource.id, 1, @rect, "snip", "body", actor: owner)

      assert_receive {^ref, :received, {:activity_annotation_created, payload}}, 500
      assert payload == %{annotation_id: annotation.id, workspace_id: workspace.id}
    end

    test "reply creation broadcasts :activity_reply_created on the workspace topic" do
      {owner, workspace} = setup_workspace("ws-pubsub-reply@example.com")
      resource = upload_resource(workspace, owner, "Calvino")

      {:ok, annotation} =
        Annotations.create_comment(resource.id, 1, @rect, "snip", "body", actor: owner)

      {ref, _peer} = subscribe_from_peer(workspace.id)

      {:ok, reply} = Annotations.reply(annotation.id, "answer", actor: owner)

      assert_receive {^ref, :received, {:activity_reply_created, payload}}, 500
      assert payload == %{reply_id: reply.id, workspace_id: workspace.id}
    end

    test "the originating process is excluded from its own broadcast" do
      {owner, workspace} = setup_workspace("ws-pubsub-self@example.com")
      resource = upload_resource(workspace, owner, "Calvino")

      :ok = ActivityPubSub.subscribe(workspace.id)

      {:ok, _} =
        Annotations.create_comment(resource.id, 1, @rect, "snip", "body", actor: owner)

      refute_receive {:activity_annotation_created, _}, 200
    end
  end
end
