defmodule StudysyncWeb.WorkspaceLiveTest do
  use StudysyncWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Workspaces

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

  describe "Index" do
    test "redirects unauthenticated users to sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/workspaces")
    end

    test "renders an empty state when the user has no workspaces", %{conn: conn} do
      user = register_user("empty@example.com")
      {:ok, _view, html} = conn |> sign_in(user) |> live(~p"/workspaces")

      assert html =~ "Workspaces"
      assert html =~ "haven&#39;t created or joined"
    end

    test "lists workspaces the user belongs to", %{conn: conn} do
      user = register_user("listuser@example.com")
      {:ok, ws} = Workspaces.create_workspace("My Reading Group", actor: user)

      {:ok, _view, html} = conn |> sign_in(user) |> live(~p"/workspaces")

      assert html =~ ws.name
    end
  end

  describe "New" do
    test "creates a workspace and navigates to its show page", %{conn: conn} do
      user = register_user("creator@example.com")
      {:ok, view, _html} = conn |> sign_in(user) |> live(~p"/workspaces/new")

      view
      |> form("#workspace-form", form: %{name: "The Calvino Group"})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ ~r"^/workspaces/[\w-]+$"
    end

    test "shows validation errors for an empty name", %{conn: conn} do
      user = register_user("validator@example.com")
      {:ok, view, _html} = conn |> sign_in(user) |> live(~p"/workspaces/new")

      html =
        view
        |> form("#workspace-form", form: %{name: ""})
        |> render_change()

      assert html =~ "input-error"
    end
  end

  describe "Show" do
    setup %{conn: conn} do
      admin = register_user("show-admin@example.com")
      {:ok, ws} = Workspaces.create_workspace("Borges Society", actor: admin)
      %{conn: sign_in(conn, admin), admin: admin, workspace: ws}
    end

    test "renders workspace name and member list", %{conn: conn, workspace: ws} do
      {:ok, _view, html} = live(conn, ~p"/workspaces/#{ws.id}")

      assert html =~ ws.name
      assert html =~ "show-admin@example.com"
      assert html =~ "admin"
      assert html =~ "active"
    end

    test "admin can invite a member by email", %{conn: conn, admin: admin, workspace: ws} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/#{ws.id}")

      view
      |> form("#invite-form", form: %{email: "invitee@example.com"})
      |> render_submit()

      memberships = Workspaces.list_memberships!(actor: admin)
      invited = Enum.find(memberships, &(to_string(&1.invite_email) == "invitee@example.com"))
      assert invited
      assert invited.status == :pending
      assert invited.role == :member
    end

    test "non-admin members do not see the invite form", %{
      conn: _admin_conn,
      admin: admin,
      workspace: ws
    } do
      member_user = register_user("member-show@example.com")
      _ = Workspaces.invite_member!(ws.id, "member-show@example.com", actor: admin)

      # accept the invite so the member is :active and can read the workspace
      [pending] =
        Studysync.Workspaces.Membership
        |> Ash.Query.filter(user_id == ^member_user.id)
        |> Ash.read!(authorize?: false)

      {:ok, _accepted} = Workspaces.accept_invite(pending, actor: member_user)

      member_conn = build_conn() |> sign_in(member_user)
      {:ok, _view, html} = live(member_conn, ~p"/workspaces/#{ws.id}")

      refute html =~ "Invite a member"
    end

    test "redirects when workspace is not visible to actor", %{conn: _conn, workspace: ws} do
      stranger = register_user("stranger-show@example.com")
      stranger_conn = build_conn() |> sign_in(stranger)

      assert {:error, {:live_redirect, %{to: "/workspaces"}}} =
               live(stranger_conn, ~p"/workspaces/#{ws.id}")
    end
  end
end
