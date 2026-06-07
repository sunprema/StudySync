defmodule Studysync.AI.CollectiveInsightJobTest do
  use Studysync.DataCase, async: true
  use Oban.Testing, repo: Studysync.Repo

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.AI.CollectiveInsightJob
  alias Studysync.Annotations
  alias Studysync.Library
  alias Studysync.Library.Storage
  alias Studysync.Progress.CollectiveInsight
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

  defp add_comment(actor, resource, page, body) do
    Annotations.create_comment!(resource.id, page, @rect, "some text", body, actor: actor)
  end

  defp run_job(resource_id, page_number) do
    perform_job(CollectiveInsightJob, %{
      "resource_id" => resource_id,
      "page_number" => page_number
    })
  end

  describe "perform/1 — happy path" do
    test "creates a CollectiveInsight when 3 distinct users annotated the same page" do
      owner = register_user("ci-owner@example.com")
      {workspace, resource} = setup_resource(owner)
      peer1 = join_workspace(workspace, owner, "ci-peer1@example.com")
      peer2 = join_workspace(workspace, owner, "ci-peer2@example.com")

      add_comment(owner, resource, 4, "owner note")
      add_comment(peer1, resource, 4, "peer1 note")
      add_comment(peer2, resource, 4, "peer2 note")

      assert :ok = run_job(resource.id, 4)

      [insight] =
        CollectiveInsight
        |> Ash.Query.filter(resource_id == ^resource.id and page_number == 4)
        |> Ash.read!(authorize?: false)

      assert insight.synthesis == "A synthesised reading-group insight generated for testing."
      assert length(insight.contributor_ids) == 3
      assert length(insight.contributing_annotation_ids) == 3
    end

    test "broadcasts :collective_insight_ready on success" do
      owner = register_user("ci-bc-owner@example.com")
      {workspace, resource} = setup_resource(owner)
      peer1 = join_workspace(workspace, owner, "ci-bc-peer1@example.com")
      peer2 = join_workspace(workspace, owner, "ci-bc-peer2@example.com")

      Phoenix.PubSub.subscribe(Studysync.PubSub, "resource:#{resource.id}")

      add_comment(owner, resource, 2, "owner note")
      add_comment(peer1, resource, 2, "peer1 note")
      add_comment(peer2, resource, 2, "peer2 note")

      assert :ok = run_job(resource.id, 2)

      assert_receive {:collective_insight_ready, %CollectiveInsight{page_number: 2}}, 2000
    end
  end

  describe "perform/1 — deduplication guard" do
    test "is a no-op when an insight already exists for the page" do
      owner = register_user("ci-dedup-owner@example.com")
      {workspace, resource} = setup_resource(owner)
      peer1 = join_workspace(workspace, owner, "ci-dedup-peer1@example.com")
      peer2 = join_workspace(workspace, owner, "ci-dedup-peer2@example.com")

      add_comment(owner, resource, 7, "first")
      add_comment(peer1, resource, 7, "second")
      add_comment(peer2, resource, 7, "third")

      assert :ok = run_job(resource.id, 7)

      # A 4th user's annotation triggers the job again — must be idempotent.
      peer3 = join_workspace(workspace, owner, "ci-dedup-peer3@example.com")
      add_comment(peer3, resource, 7, "fourth")

      assert :ok = run_job(resource.id, 7)

      count =
        CollectiveInsight
        |> Ash.Query.filter(resource_id == ^resource.id and page_number == 7)
        |> Ash.count!(authorize?: false)

      assert count == 1
    end
  end

  describe "perform/1 — fewer than 3 contributors" do
    test "does nothing with only 1 annotator" do
      owner = register_user("ci-few-owner@example.com")
      {_ws, resource} = setup_resource(owner)

      add_comment(owner, resource, 1, "solo note")

      assert :ok = run_job(resource.id, 1)

      count =
        CollectiveInsight
        |> Ash.Query.filter(resource_id == ^resource.id and page_number == 1)
        |> Ash.count!(authorize?: false)

      assert count == 0
    end

    test "does nothing with only 2 distinct annotators" do
      owner = register_user("ci-two-owner@example.com")
      {workspace, resource} = setup_resource(owner)
      peer1 = join_workspace(workspace, owner, "ci-two-peer1@example.com")

      add_comment(owner, resource, 3, "one")
      add_comment(peer1, resource, 3, "two")

      assert :ok = run_job(resource.id, 3)

      count =
        CollectiveInsight
        |> Ash.Query.filter(resource_id == ^resource.id and page_number == 3)
        |> Ash.count!(authorize?: false)

      assert count == 0
    end
  end
end
