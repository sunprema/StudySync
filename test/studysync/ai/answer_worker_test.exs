defmodule Studysync.AI.AnswerWorkerTest do
  # async: false because some tests override Application env for the AI stub.
  use Studysync.DataCase, async: false
  use Oban.Testing, repo: Studysync.Repo

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.AI.AnswerWorker
  alias Studysync.Annotations
  alias Studysync.Annotations.AnnotationComment
  alias Studysync.Library
  alias Studysync.Library.Storage
  alias Studysync.Workspaces

  # Reset the AI stub to the test default before every test so env-overriding
  # tests in this module don't bleed into each other.
  setup do
    stub = fn _messages, _opts -> {:ok, "A synthesised reading-group insight generated for testing."} end
    Application.put_env(:studysync, :ai_complete_fn, stub)
    on_exit(fn -> Application.put_env(:studysync, :ai_complete_fn, stub) end)
    :ok
  end

  @minimal_pdf """
  %PDF-1.4
  1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
  2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
  3 0 obj << /Type /Page /Parent 2 0 R >> endobj
  trailer << /Root 1 0 R >>
  %%EOF
  """

  @rect %{"x" => 0.1, "y" => 0.2, "width" => 0.4, "height" => 0.05}

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
    workspace = Workspaces.create_workspace!("Test Group", actor: owner)

    resource =
      Library.upload_resource!(
        workspace.id,
        "Test Book",
        %{content: @minimal_pdf, filename: "test.pdf"},
        actor: owner
      )

    on_exit(fn -> Storage.delete(resource.file_path) end)
    {workspace, resource}
  end

  defp create_annotation(actor, resource, body \\ "What does this mean?") do
    Annotations.create_question!(
      resource.id,
      1,
      @rect,
      "a highlighted passage",
      body,
      actor: actor
    )
  end

  defp run_job(annotation_id) do
    perform_job(AnswerWorker, %{"annotation_id" => annotation_id})
  end

  describe "perform/1 — happy path" do
    test "writes an ai_reply comment on the annotation" do
      owner = register_user("aw-happy@example.com")
      {_ws, resource} = setup_resource(owner)
      annotation = create_annotation(owner, resource)

      assert :ok = run_job(annotation.id)

      [reply] =
        AnnotationComment
        |> Ash.Query.filter(annotation_id == ^annotation.id)
        |> Ash.read!(authorize?: false)

      assert reply.is_ai_response == true
      assert reply.body == "A synthesised reading-group insight generated for testing."
      assert is_nil(reply.user_id)
    end

    test "broadcasts :reply_created on the resource topic" do
      owner = register_user("aw-broadcast@example.com")
      {_ws, resource} = setup_resource(owner)
      annotation = create_annotation(owner, resource, "I'm curious about this.")

      # broadcast_from! skips the sending process, so subscribe from a
      # separate process that isn't the job runner.
      test_pid = self()
      topic = "resource:#{resource.id}"

      subscriber =
        spawn(fn ->
          Phoenix.PubSub.subscribe(Studysync.PubSub, topic)
          send(test_pid, :subscribed)

          receive do
            msg -> send(test_pid, {:got, msg})
          after
            3000 -> send(test_pid, :timeout)
          end
        end)

      assert_receive :subscribed, 1000

      assert :ok = run_job(annotation.id)

      annotation_id = annotation.id
      resource_id = resource.id

      assert_receive {:got,
                      {:reply_created,
                       %{annotation_id: ^annotation_id, resource_id: ^resource_id}}},
                     3000

      Process.exit(subscriber, :kill)
    end
  end

  describe "perform/1 — annotation not found" do
    test "returns :ok without error when annotation has been deleted" do
      non_existent_id = Ash.UUID.generate()
      assert :ok = run_job(non_existent_id)
    end
  end

  describe "perform/1 — AI failure" do
    test "writes a graceful error reply on final attempt" do
      owner = register_user("aw-failure@example.com")
      {_ws, resource} = setup_resource(owner)
      annotation = create_annotation(owner, resource, "puzzling passage")

      Application.put_env(:studysync, :ai_complete_fn, fn _m, _o -> {:error, :timeout} end)

      # Simulate final attempt (attempt == max_attempts)
      assert :ok =
               perform_job(AnswerWorker, %{"annotation_id" => annotation.id},
                 attempt: 3,
                 max_attempts: 3
               )

      [reply] =
        AnnotationComment
        |> Ash.Query.filter(annotation_id == ^annotation.id)
        |> Ash.read!(authorize?: false)

      assert reply.is_ai_response == true
      assert String.contains?(reply.body, "try again")
    end

    test "returns {:error, reason} on non-final attempt so Oban retries" do
      owner = register_user("aw-retry@example.com")
      {_ws, resource} = setup_resource(owner)
      annotation = create_annotation(owner, resource, "another question")

      Application.put_env(:studysync, :ai_complete_fn, fn _m, _o -> {:error, :timeout} end)

      assert {:error, :timeout} =
               perform_job(AnswerWorker, %{"annotation_id" => annotation.id},
                 attempt: 1,
                 max_attempts: 3
               )

      # No reply written — Oban will retry.
      count =
        AnnotationComment
        |> Ash.Query.filter(annotation_id == ^annotation.id)
        |> Ash.count!(authorize?: false)

      assert count == 0
    end
  end

  describe "perform/1 — includes thread context" do
    test "fetches existing replies and includes them in the prompt" do
      owner = register_user("aw-context@example.com")
      {_ws, resource} = setup_resource(owner)
      annotation = create_annotation(owner, resource, "first question")

      # Add a reply so there is thread context.
      Annotations.reply!(annotation.id, "a reader reply", actor: owner)

      assert :ok = run_job(annotation.id)

      count =
        AnnotationComment
        |> Ash.Query.filter(annotation_id == ^annotation.id and is_ai_response == true)
        |> Ash.count!(authorize?: false)

      assert count == 1
    end
  end
end
