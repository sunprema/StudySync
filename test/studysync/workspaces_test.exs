defmodule Studysync.WorkspacesTest do
  use Studysync.DataCase, async: true

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Workspaces
  alias Studysync.Workspaces.Membership

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

  describe "create_workspace/2" do
    test "requires an actor" do
      assert_raise Ash.Error.Forbidden, fn ->
        Workspaces.create_workspace!("Anonymous", actor: nil)
      end
    end

    test "creates a workspace and gives the creator an admin/active membership" do
      user = register_user("ada@example.com")
      workspace = build_workspace(user, "Lovelace's Notebooks")

      assert workspace.name == "Lovelace's Notebooks"

      [membership] =
        Membership
        |> Ash.Query.filter(workspace_id == ^workspace.id)
        |> Ash.read!(authorize?: false)

      assert membership.user_id == user.id
      assert membership.role == :admin
      assert membership.status == :active
    end

    test "validates name presence" do
      user = register_user("blank-name@example.com")

      assert {:error, %Ash.Error.Invalid{}} = Workspaces.create_workspace("", actor: user)
    end
  end

  describe "workspace read policy" do
    test "members can read workspaces they belong to" do
      owner = register_user("owner@example.com")
      workspace = build_workspace(owner)

      assert {:ok, fetched} = Workspaces.get_workspace(workspace.id, actor: owner)
      assert fetched.id == workspace.id
    end

    test "non-members cannot read a workspace" do
      owner = register_user("owner2@example.com")
      stranger = register_user("stranger@example.com")
      workspace = build_workspace(owner)

      # Filter-based policies make the row invisible to non-members; the
      # `get_by: [:id]` interface treats that as not-found.
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Workspaces.get_workspace(workspace.id, actor: stranger)
    end

    test "list_workspaces only returns workspaces the actor belongs to" do
      ada = register_user("ada-list@example.com")
      bob = register_user("bob-list@example.com")
      ada_ws = build_workspace(ada, "Ada's group")
      _bob_ws = build_workspace(bob, "Bob's group")

      ada_results = Workspaces.list_workspaces!(actor: ada)
      assert Enum.map(ada_results, & &1.id) == [ada_ws.id]
    end
  end

  describe "invite_member/3" do
    test "admin can invite an existing user — creates pending membership with user_id" do
      admin = register_user("admin1@example.com")
      invitee = register_user("invitee@example.com")
      workspace = build_workspace(admin)

      membership = Workspaces.invite_member!(workspace.id, "invitee@example.com", actor: admin)

      assert membership.user_id == invitee.id
      assert membership.status == :pending
      assert membership.role == :member
      assert membership.invite_email == nil
    end

    test "admin can invite a non-existing email — creates pending membership with invite_email" do
      admin = register_user("admin2@example.com")
      workspace = build_workspace(admin)

      membership =
        Workspaces.invite_member!(workspace.id, "future-user@example.com", actor: admin)

      assert membership.user_id == nil
      assert to_string(membership.invite_email) == "future-user@example.com"
      assert membership.status == :pending
    end

    test "non-admin members cannot invite" do
      admin = register_user("admin3@example.com")
      member_user = register_user("member3@example.com")
      workspace = build_workspace(admin)

      # promote the member into the workspace (still as :member)
      _ = Workspaces.invite_member!(workspace.id, "member3@example.com", actor: admin)

      assert_raise Ash.Error.Forbidden, fn ->
        Workspaces.invite_member!(workspace.id, "another@example.com", actor: member_user)
      end
    end

    test "strangers cannot invite" do
      admin = register_user("admin4@example.com")
      stranger = register_user("stranger4@example.com")
      workspace = build_workspace(admin)

      assert_raise Ash.Error.Forbidden, fn ->
        Workspaces.invite_member!(workspace.id, "anyone@example.com", actor: stranger)
      end
    end
  end

  describe "membership read policy" do
    test "active members can read all memberships of their workspace" do
      admin = register_user("admin5@example.com")
      workspace = build_workspace(admin)
      _ = Workspaces.invite_member!(workspace.id, "guest5@example.com", actor: admin)

      results =
        Membership
        |> Ash.Query.filter(workspace_id == ^workspace.id)
        |> Ash.read!(actor: admin)

      assert length(results) == 2
    end

    test "non-members see nothing" do
      admin = register_user("admin6@example.com")
      stranger = register_user("stranger6@example.com")
      workspace = build_workspace(admin)
      _ = Workspaces.invite_member!(workspace.id, "guest6@example.com", actor: admin)

      results =
        Membership
        |> Ash.Query.filter(workspace_id == ^workspace.id)
        |> Ash.read!(actor: stranger)

      assert results == []
    end
  end

  describe "accept invite" do
    test "an invited user can accept their pending membership" do
      admin = register_user("admin7@example.com")
      invitee = register_user("invitee7@example.com")
      workspace = build_workspace(admin)

      pending = Workspaces.invite_member!(workspace.id, "invitee7@example.com", actor: admin)
      assert pending.status == :pending

      {:ok, accepted} = Workspaces.accept_invite(pending, actor: invitee)
      assert accepted.status == :active
    end

    test "another user cannot accept someone else's pending membership" do
      admin = register_user("admin8@example.com")
      invitee = register_user("invitee8@example.com")
      stranger = register_user("stranger8@example.com")
      workspace = build_workspace(admin)

      pending = Workspaces.invite_member!(workspace.id, "invitee8@example.com", actor: admin)
      assert pending.user_id == invitee.id

      assert {:error, %Ash.Error.Forbidden{}} =
               Workspaces.accept_invite(pending, actor: stranger)
    end
  end
end
