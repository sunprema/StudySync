defmodule StudysyncWeb.ResourceJournalControllerTest do
  use StudysyncWeb.ConnCase, async: true

  alias Studysync.Accounts
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

  defp sign_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  defp setup_resource(owner) do
    workspace = Workspaces.create_workspace!("Reading Group", actor: owner)

    resource =
      Library.upload_resource!(
        workspace.id,
        "Invisible Cities",
        %{content: @minimal_pdf, filename: "calvino.pdf"},
        actor: owner
      )

    on_exit(fn -> Storage.delete(resource.file_path) end)
    {workspace, resource}
  end

  describe "GET /resources/:id/journal.pdf" do
    test "returns PDF for a workspace member", %{conn: conn} do
      user = register_user("member@example.com")
      {_ws, resource} = setup_resource(user)

      conn =
        conn
        |> sign_in(user)
        |> get(~p"/resources/#{resource.id}/journal.pdf")

      assert conn.status == 200
      assert List.first(get_resp_header(conn, "content-type")) =~ "application/pdf"

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ "journal.pdf"
    end

    test "returns 404 for a non-member", %{conn: conn} do
      owner = register_user("owner@journal-test.com")
      stranger = register_user("stranger@journal-test.com")
      {_ws, resource} = setup_resource(owner)

      conn =
        conn
        |> sign_in(stranger)
        |> get(~p"/resources/#{resource.id}/journal.pdf")

      assert conn.status == 404
    end

    test "returns 404 for an unknown resource id", %{conn: conn} do
      user = register_user("user@journal-test.com")
      _setup = setup_resource(user)

      conn =
        conn
        |> sign_in(user)
        |> get(~p"/resources/#{Ash.UUID.generate()}/journal.pdf")

      assert conn.status == 404
    end
  end
end
