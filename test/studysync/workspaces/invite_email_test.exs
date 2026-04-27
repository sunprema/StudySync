defmodule Studysync.Workspaces.InviteEmailTest do
  @moduledoc """
  1.8a — invite emails get sent and the embedded token round-trips.
  1.8b — registering a user with a pending-invite email claims the row.
  """
  use Studysync.DataCase, async: false

  import Swoosh.TestAssertions

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Workspaces
  alias Studysync.Workspaces.Membership
  alias Studysync.Workspaces.Membership.Senders.SendInviteEmail

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

  # The Swoosh test adapter pushes `{:email, _}` to the current process per
  # delivery; user registration sends a confirmation email we don't care about
  # in invite tests, so flush before the action under test.
  defp drain_mailbox do
    receive do
      {:email, _} -> drain_mailbox()
    after
      0 -> :ok
    end
  end

  describe "1.8a — sender" do
    test "delivers an email when an existing user is invited" do
      admin = register_user("admin-email1@example.com")
      _invitee = register_user("invitee-email1@example.com")
      workspace = build_workspace(admin, "Bookworms")

      drain_mailbox()
      _ = Workspaces.invite_member!(workspace.id, "invitee-email1@example.com", actor: admin)

      assert_email_sent(fn email ->
        match?({_, "invitee-email1@example.com"}, hd(email.to)) and
          email.subject == "You're invited to Bookworms" and
          email.html_body =~ "Bookworms" and
          email.html_body =~ "/invites/"
      end)
    end

    test "delivers an email when an unregistered email is invited" do
      admin = register_user("admin-email2@example.com")
      workspace = build_workspace(admin, "Future Readers")

      drain_mailbox()
      _ = Workspaces.invite_member!(workspace.id, "future@example.com", actor: admin)

      assert_email_sent(fn email ->
        match?({_, "future@example.com"}, hd(email.to)) and
          email.subject == "You're invited to Future Readers"
      end)
    end

    test "token round-trips" do
      assert {:ok, "abc-123"} =
               "abc-123"
               |> SendInviteEmail.sign_token()
               |> SendInviteEmail.verify_token()
    end

    test "rejects malformed tokens" do
      assert {:error, :invalid} = SendInviteEmail.verify_token("not-a-token")
    end
  end

  describe "1.8b — claim on signup" do
    test "registering with a matching invite_email attaches user_id" do
      admin = register_user("admin-claim@example.com")
      workspace = build_workspace(admin)

      pending =
        Workspaces.invite_member!(workspace.id, "incoming@example.com", actor: admin)

      assert pending.user_id == nil
      assert to_string(pending.invite_email) == "incoming@example.com"

      new_user = register_user("incoming@example.com")

      reloaded =
        Membership
        |> Ash.Query.filter(id == ^pending.id)
        |> Ash.read_one!(authorize?: false)

      assert reloaded.user_id == new_user.id
      assert reloaded.status == :pending
    end

    test "leaves unrelated invites alone" do
      admin = register_user("admin-claim2@example.com")
      workspace = build_workspace(admin)

      pending =
        Workspaces.invite_member!(workspace.id, "someone@example.com", actor: admin)

      _ = register_user("different@example.com")

      reloaded =
        Membership
        |> Ash.Query.filter(id == ^pending.id)
        |> Ash.read_one!(authorize?: false)

      assert reloaded.user_id == nil
      assert to_string(reloaded.invite_email) == "someone@example.com"
    end
  end
end
