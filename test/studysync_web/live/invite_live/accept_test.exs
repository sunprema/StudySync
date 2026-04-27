defmodule StudysyncWeb.InviteLive.AcceptTest do
  @moduledoc """
  1.8a — `/invites/:token` accept LiveView. Covers the four user-facing
  branches: signed-out, ready-to-accept, wrong user, and already a member.
  """
  use StudysyncWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  defp setup_invite(invitee_email) do
    admin = register_user("invite-admin-#{System.unique_integer([:positive])}@example.com")
    workspace = Workspaces.create_workspace!("Margin Society", actor: admin)
    membership = Workspaces.invite_member!(workspace.id, invitee_email, actor: admin)
    %{admin: admin, workspace: workspace, membership: membership}
  end

  test "invalid token shows expired state", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/invites/garbage-token")
    assert html =~ "Invitation expired"
  end

  test "signed-out user sees a sign-in prompt", %{conn: conn} do
    %{membership: membership} = setup_invite("signed-out@example.com")
    token = SendInviteEmail.sign_token(membership.id)

    {:ok, _view, html} = live(conn, ~p"/invites/#{token}")

    assert html =~ "Sign in"
    assert html =~ "signed-out@example.com"
  end

  test "wrong signed-in user is blocked", %{conn: conn} do
    %{membership: _m} = setup_invite("real-invitee@example.com")
    invitee = register_user("real-invitee@example.com")

    %{membership: membership} = setup_invite("real-invitee@example.com")
    _ = invitee
    token = SendInviteEmail.sign_token(membership.id)

    stranger = register_user("stranger-accept@example.com")

    {:ok, _view, html} = conn |> sign_in(stranger) |> live(~p"/invites/#{token}")

    assert html =~ "Not your invitation"
  end

  test "correct signed-in user can accept", %{conn: conn} do
    invitee = register_user("happy-path@example.com")
    %{membership: membership, workspace: workspace} = setup_invite("happy-path@example.com")
    token = SendInviteEmail.sign_token(membership.id)

    {:ok, view, _html} = conn |> sign_in(invitee) |> live(~p"/invites/#{token}")

    assert render(view) =~ "Join Margin Society"

    result = view |> element("button", "Accept invitation") |> render_click()

    assert {:error, {:live_redirect, %{to: redirect}}} = result
    assert redirect == "/workspaces/#{workspace.id}"

    accepted =
      Membership
      |> Ash.Query.filter(id == ^membership.id)
      |> Ash.read_one!(authorize?: false)

    assert accepted.status == :active
  end

  test "already-active membership shows already-a-member state", %{conn: conn} do
    invitee = register_user("already-in@example.com")
    %{membership: membership} = setup_invite("already-in@example.com")
    {:ok, _accepted} = Workspaces.accept_invite(membership, actor: invitee)

    token = SendInviteEmail.sign_token(membership.id)

    {:ok, _view, html} = conn |> sign_in(invitee) |> live(~p"/invites/#{token}")

    assert html =~ "Already a member"
  end
end
