defmodule Studysync.ChatTest do
  use Studysync.DataCase, async: true

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Chat
  alias Studysync.Chat.{Buffer, Message, PubSub}
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
        "Calvino — Invisible Cities",
        %{content: @minimal_pdf, filename: "calvino.pdf"},
        actor: owner
      )

    on_exit(fn -> Storage.delete(resource.file_path) end)

    {owner, workspace, resource}
  end

  defp add_member(workspace_id, owner, email) do
    member = register_user(email)
    _ = Workspaces.invite_member!(workspace_id, email, actor: owner)

    [pending] =
      Studysync.Workspaces.Membership
      |> Ash.Query.filter(user_id == ^member.id)
      |> Ash.read!(authorize?: false)

    {:ok, _} = Workspaces.accept_invite(pending, actor: member)
    member
  end

  describe "send_message/3" do
    test "a workspace member can send a message and it lands in the buffer" do
      {owner, _ws, resource} = setup_resource("chat-owner@example.com")

      assert {:ok, %Message{} = message} =
               Chat.send_message(owner, resource.id, "first thoughts")

      assert message.user_id == owner.id
      assert message.user_email == owner.email |> to_string()
      assert message.body == "first thoughts"
      assert message.resource_id == resource.id
      assert %DateTime{} = message.sent_at

      assert [^message] = Chat.recent(resource.id)
    end

    test "an invited active member can send a message" do
      {owner, ws, resource} = setup_resource("chat-owner-mem@example.com")
      member = add_member(ws.id, owner, "chat-member@example.com")

      assert {:ok, %Message{user_id: user_id}} =
               Chat.send_message(member, resource.id, "joining the conversation")

      assert user_id == member.id
    end

    test "a non-member is rejected and nothing hits the buffer" do
      {_owner, _ws, resource} = setup_resource("chat-stranger-owner@example.com")
      stranger = register_user("chat-stranger@example.com")

      assert {:error, :unauthorized} =
               Chat.send_message(stranger, resource.id, "i shouldn't be here")

      assert Chat.recent(resource.id) == []
    end

    test "an empty body is rejected" do
      {owner, _ws, resource} = setup_resource("chat-empty@example.com")

      assert {:error, :empty_body} = Chat.send_message(owner, resource.id, "   ")
      assert Chat.recent(resource.id) == []
    end

    test "an oversized body is rejected" do
      {owner, _ws, resource} = setup_resource("chat-toolong@example.com")
      body = String.duplicate("x", Chat.max_body_length() + 1)

      assert {:error, :body_too_long} = Chat.send_message(owner, resource.id, body)
      assert Chat.recent(resource.id) == []
    end

    test "rate limit kicks in on the 6th message in the window" do
      {owner, _ws, resource} = setup_resource("chat-rate@example.com")
      n = Buffer.rate_limit_count()

      for i <- 1..n do
        assert {:ok, _} = Chat.send_message(owner, resource.id, "msg #{i}")
      end

      assert {:error, :rate_limited} = Chat.send_message(owner, resource.id, "one too many")
    end

    test "the ring buffer caps at the configured max" do
      {owner, _ws, resource} = setup_resource("chat-ring@example.com")
      max = Buffer.max_messages()

      # Insert directly into the buffer with a unique synthetic user_id per
      # message — keeps every send under the per-user rate limit so we can
      # exercise the trim independently of the limiter.
      for i <- 1..(max + 1) do
        synthetic_user = owner.id <> "-#{i}"
        {:ok, _} = Buffer.append(resource.id, synthetic_user, "u#{i}@x.com", "ring #{i}")
      end

      messages = Chat.recent(resource.id)
      assert length(messages) == max
      assert hd(messages).body == "ring 2"
      assert List.last(messages).body == "ring #{max + 1}"
    end
  end

  describe "PubSub broadcast" do
    test "subscribers receive {:chat_message, %Message{}} on send" do
      {owner, ws, resource} = setup_resource("chat-bcast-owner@example.com")
      member = add_member(ws.id, owner, "chat-bcast-member@example.com")

      # Subscribe as a different process so we receive the broadcast (the
      # sender is excluded by broadcast_from!).
      parent = self()

      Task.start_link(fn ->
        :ok = PubSub.subscribe(resource.id)
        send(parent, :ready)

        receive do
          {:chat_message, %Message{} = msg} -> send(parent, {:got, msg})
        after
          1_000 -> send(parent, :timeout)
        end
      end)

      assert_receive :ready, 1_000

      assert {:ok, %Message{id: id}} = Chat.send_message(member, resource.id, "hello room")

      assert_receive {:got, %Message{id: ^id, body: "hello room"}}, 1_000
    end

    test "the sender does not receive its own broadcast" do
      {owner, _ws, resource} = setup_resource("chat-self-skip@example.com")

      :ok = PubSub.subscribe(resource.id)

      assert {:ok, %Message{}} = Chat.send_message(owner, resource.id, "self-cast?")

      refute_receive {:chat_message, _}, 200

      :ok = PubSub.unsubscribe(resource.id)
    end
  end

  describe "recent/2" do
    test "returns at most n messages, oldest first" do
      {owner, _ws, resource} = setup_resource("chat-recent@example.com")

      for i <- 1..3 do
        {:ok, _} = Buffer.append(resource.id, owner.id, to_string(owner.email), "m#{i}")
      end

      messages = Chat.recent(resource.id, 2)
      assert Enum.map(messages, & &1.body) == ["m2", "m3"]
    end

    test "returns [] for a resource with no messages" do
      assert Chat.recent(Ecto.UUID.generate()) == []
    end
  end
end
