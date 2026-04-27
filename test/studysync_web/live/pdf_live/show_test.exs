defmodule StudysyncWeb.PdfLive.ShowTest do
  use StudysyncWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Annotations
  alias Studysync.Library
  alias Studysync.Library.Storage
  alias Studysync.Workspaces

  @minimal_pdf """
  %PDF-1.4
  1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
  2 0 obj << /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >> endobj
  3 0 obj << /Type /Page /Parent 2 0 R >> endobj
  4 0 obj << /Type /Page /Parent 2 0 R >> endobj
  5 0 obj << /Type /Page /Parent 2 0 R >> endobj
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

  setup do
    user = register_user("reader@example.com")
    workspace = Workspaces.create_workspace!("Reading Group", actor: user)

    resource =
      Library.upload_resource!(
        workspace.id,
        "Calvino — Invisible Cities",
        %{content: @minimal_pdf, filename: "calvino.pdf"},
        actor: user
      )

    on_exit(fn -> Storage.delete(resource.file_path) end)

    %{user: user, workspace: workspace, resource: resource}
  end

  describe "PdfLive.Show mount + render" do
    test "renders three-column shell with chapter rail, canvas mount, and margin column", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, _view, html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # Three-column shell pieces — assert the structural anchors exist.
      assert html =~ ~s(aria-label="Chapters")
      assert html =~ ~s(id="pdf-canvas")
      assert html =~ "Margin ·"

      # Resource title in the header
      assert html =~ "Calvino"
      # Page count indicator (mono small caps)
      assert html =~ ~r{<span class="num">3</span>\s*pages}
    end

    test "non-members are redirected back to the library", %{
      conn: conn,
      workspace: ws,
      resource: r
    } do
      stranger = register_user("stranger-pdf@example.com")

      assert {:error, {:live_redirect, %{to: target}}} =
               conn
               |> sign_in(stranger)
               |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      assert target == "/workspaces/#{ws.id}/library"
    end

    test "redirects to the library when the resource id does not belong to the workspace in the URL",
         %{conn: conn, user: user, resource: r} do
      other_ws = Workspaces.create_workspace!("Other group", actor: user)

      assert {:error, {:live_redirect, %{to: target}}} =
               conn
               |> sign_in(user)
               |> live(~p"/workspaces/#{other_ws.id}/library/#{r.id}")

      assert target == "/workspaces/#{other_ws.id}/library"
    end
  end

  describe "annotations" do
    setup %{user: user, resource: resource} do
      {:ok, annotation} =
        Annotations.create_comment(
          resource.id,
          1,
          %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05},
          "of cities and signs",
          "what does this passage mean?",
          actor: user
        )

      %{annotation: annotation}
    end

    test "mount renders existing annotations in the margin column", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r,
      annotation: a
    } do
      {:ok, _view, html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      assert html =~ "Margin · "
      assert html =~ ~r{<span class="num">1</span>\s*notes}
      assert html =~ ~s(id="margin-note-#{a.id}")
      assert html =~ "of cities and signs"
      assert html =~ "what does this passage mean?"
    end

    test "text_selected event opens the annotation form with the snippet", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      html =
        render_hook(view, "text_selected", %{
          "text" => "the city of Diomira",
          "page" => 1,
          "rect" => %{"x" => 0.2, "y" => 0.4, "width" => 0.25, "height" => 0.04}
        })

      assert html =~ "New note · page"
      assert html =~ "the city of Diomira"
      assert has_element?(view, "#annotation-form")
    end

    test "submitting the form persists the annotation and closes the form", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      render_hook(view, "text_selected", %{
        "text" => "Sophronia is a city of two halves",
        "page" => 1,
        "rect" => %{"x" => 0.15, "y" => 0.5, "width" => 0.4, "height" => 0.04}
      })

      view
      |> form("#annotation-form", form: %{body: "split-personality city"})
      |> render_submit()

      results =
        Annotations.list_annotations!(
          actor: user,
          query: [filter: [resource_id: r.id]]
        )

      assert Enum.any?(results, &(&1.body == "split-personality city"))
      refute has_element?(view, "#annotation-form")
    end

    test "cancel button dismisses the form without persisting", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      render_hook(view, "text_selected", %{
        "text" => "snippet",
        "page" => 1,
        "rect" => %{"x" => 0.1, "y" => 0.1, "width" => 0.1, "height" => 0.05}
      })

      assert has_element?(view, "#annotation-form")

      view
      |> element("button[phx-click=cancel_annotation]")
      |> render_click()

      refute has_element?(view, "#annotation-form")
    end
  end

  describe "bi-directional sync (Slice 5)" do
    setup %{user: user, resource: resource} do
      {:ok, a1} =
        Annotations.create_comment(
          resource.id,
          1,
          %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05},
          "first snippet",
          "first body",
          actor: user
        )

      {:ok, a2} =
        Annotations.create_comment(
          resource.id,
          2,
          %{"x" => 0.2, "y" => 0.4, "width" => 0.2, "height" => 0.05},
          "second snippet",
          "second body",
          actor: user
        )

      %{a1: a1, a2: a2}
    end

    # The terracotta border lands on the active note as `border-terracotta `
    # (whitespace-bounded). Inactive notes use `border-paper-2 hover:border-terracotta/50`,
    # so plain "border-terracotta" appears in both — match the trailing space
    # plus follow-on bg-paper class to disambiguate.
    defp active?(html, id) do
      Regex.match?(
        ~r{id="margin-note-#{id}"[^>]*\sborder-terracotta\sbg-paper},
        html
      )
    end

    test "clicking a margin note marks it active and styles the border terracotta",
         %{conn: conn, user: user, workspace: ws, resource: r, a1: a1, a2: a2} do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      html =
        view
        |> element("#margin-note-#{a2.id}")
        |> render_click()

      assert active?(html, a2.id)
      refute active?(html, a1.id)
    end

    test "annotation_clicked from the canvas marks the matching margin note active",
         %{conn: conn, user: user, workspace: ws, resource: r, a1: a1} do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      html = render_hook(view, "annotation_clicked", %{"id" => a1.id})

      assert active?(html, a1.id)

      # And the LiveView should have pushed a scroll event for the margin
      # column hook to react to.
      assert_push_event(view, "scroll_to_margin_note", %{id: id})
      assert id == a1.id
    end

    test "select_annotation flips the active id when a different note is clicked",
         %{conn: conn, user: user, workspace: ws, resource: r, a1: a1, a2: a2} do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      view |> element("#margin-note-#{a1.id}") |> render_click()
      html = view |> element("#margin-note-#{a2.id}") |> render_click()

      assert active?(html, a2.id)
      refute active?(html, a1.id)
    end
  end

  describe "annotation threads (Slice 6)" do
    setup %{user: user, resource: resource} do
      {:ok, annotation} =
        Annotations.create_comment(
          resource.id,
          1,
          %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05},
          "of cities and signs",
          "what does this passage mean?",
          actor: user
        )

      %{annotation: annotation}
    end

    test "collapsed margin note shows a Reply control when there are no replies", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r,
      annotation: a
    } do
      {:ok, _view, html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # Reply control sits inside the margin note article
      assert html =~ ~s(aria-controls="thread-#{a.id}")
      assert html =~ ~s(aria-expanded="false")

      # Match the toggle button — when there are zero replies, its label is "Reply".
      assert Regex.match?(
               ~r{aria-controls="thread-#{a.id}"[^>]*>\s*Reply\s*</button>}s,
               html
             )
    end

    test "toggling expands the thread, shows the reply form, and toggling again collapses it", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r,
      annotation: a
    } do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # Expand
      html =
        view
        |> element(~s(button[aria-controls="thread-#{a.id}"]))
        |> render_click()

      assert html =~ ~s(id="thread-#{a.id}")
      assert html =~ ~s(id="reply-form-#{a.id}")
      assert html =~ ~s(aria-expanded="true")

      # Collapse
      html =
        view
        |> element(~s(button[aria-controls="thread-#{a.id}"]))
        |> render_click()

      refute html =~ ~s(id="reply-form-#{a.id}")
      assert html =~ ~s(aria-expanded="false")
    end

    test "submitting the reply form persists a reply and re-renders the thread with it", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r,
      annotation: a
    } do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      view
      |> element(~s(button[aria-controls="thread-#{a.id}"]))
      |> render_click()

      reply_body = "Memory and signs entwine."

      html =
        view
        |> form("#reply-form-#{a.id}", form: %{body: reply_body})
        |> render_submit()

      # Reply persisted
      replies =
        Annotations.list_replies!(
          actor: user,
          query: [filter: [annotation_id: a.id]]
        )

      assert Enum.any?(replies, &(&1.body == reply_body))

      # Reply rendered in the thread
      assert html =~ reply_body

      # Reply count badge updates on the (still-expanded) note when collapsed
      collapse_html =
        view
        |> element(~s(button[aria-controls="thread-#{a.id}"]))
        |> render_click()

      assert collapse_html =~ "1 reply"
    end
  end

  describe "real-time collaboration (Slice 7)" do
    setup %{user: user, workspace: ws} do
      member = register_user("rt-member@example.com")

      _ = Workspaces.invite_member!(ws.id, "rt-member@example.com", actor: user)

      [pending] =
        Studysync.Workspaces.Membership
        |> Ash.Query.filter(user_id == ^member.id)
        |> Ash.read!(authorize?: false)

      {:ok, _} = Workspaces.accept_invite(pending, actor: member)

      %{member: member}
    end

    # The action runs in the test process, broadcast_from! skips the test
    # process, the LiveView process is the only subscriber → it receives,
    # patches its assigns, and the next render reflects the change.
    test "an annotation created out-of-band shows up in an open reader's margin", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r,
      member: member
    } do
      {:ok, view, html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      assert html =~ ~r{Margin · <span class="num">0</span>}

      {:ok, _annotation} =
        Annotations.create_comment(
          r.id,
          1,
          %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05},
          "broadcast snippet",
          "broadcast body",
          actor: member
        )

      patched = render(view)

      assert patched =~ "broadcast snippet"
      assert patched =~ "broadcast body"
      assert patched =~ ~r{Margin · <span class="num">1</span>}
    end

    test "a reply created out-of-band bumps the reply count badge", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r,
      member: member
    } do
      {:ok, annotation} =
        Annotations.create_comment(
          r.id,
          1,
          %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05},
          "of cities",
          "what is this passage?",
          actor: user
        )

      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      {:ok, _reply} =
        Annotations.reply(annotation.id, "I think it's about memory.", actor: member)

      patched = render(view)

      assert patched =~ "1 reply"
      refute patched =~ "I think it's about memory."

      # When the thread is expanded, the same broadcast lands the reply body
      # too — refetched through Ash so read policies still apply.
      view
      |> element(~s(button[aria-controls="thread-#{annotation.id}"]))
      |> render_click()

      {:ok, _reply2} =
        Annotations.reply(annotation.id, "Memory and signs entwine.", actor: member)

      after_expand = render(view)

      assert after_expand =~ "Memory and signs entwine."

      # When expanded the toggle reads "Hide thread"; collapse to surface the
      # updated count badge.
      collapsed =
        view
        |> element(~s(button[aria-controls="thread-#{annotation.id}"]))
        |> render_click()

      assert collapsed =~ "2 replies"
    end

    test "two open readers each see the other's annotation appear", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r,
      member: member
    } do
      {:ok, view_a, _} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      {:ok, view_b, _} =
        Phoenix.ConnTest.build_conn()
        |> sign_in(member)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      {:ok, _} =
        Annotations.create_comment(
          r.id,
          1,
          %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05},
          "shared thought",
          "shared body",
          actor: member
        )

      assert render(view_a) =~ "shared thought"
      assert render(view_b) =~ "shared thought"
    end
  end

  describe "annotation types & filter chips (Slice 10)" do
    setup %{user: user, resource: resource} do
      rect = %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05}

      {:ok, comment} =
        Annotations.create_comment(resource.id, 1, rect, "comment-snippet", "comment body",
          actor: user
        )

      {:ok, question} =
        Annotations.create_question(resource.id, 2, rect, "question-snippet", "question body",
          actor: user
        )

      {:ok, puzzle} =
        Annotations.create_puzzle(resource.id, 3, rect, "puzzle-snippet", "puzzle body",
          actor: user
        )

      %{comment: comment, question: question, puzzle: puzzle}
    end

    test "filter chips render with per-type counts", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, _view, html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      assert html =~ ~s(phx-value-type="all")
      assert html =~ ~s(phx-value-type="comment")
      assert html =~ ~s(phx-value-type="question")
      assert html =~ ~s(phx-value-type="puzzle")

      # The "All" chip is active on mount and shows the total count of 3.
      assert Regex.match?(
               ~r{phx-value-type="all"[^>]*aria-pressed="true"[^>]*>\s*All\s*<span[^>]*>3</span>}s,
               html
             )

      # Each per-type chip shows its individual count of 1.
      assert Regex.match?(
               ~r{phx-value-type="comment"[^>]*>\s*Comments\s*<span[^>]*>1</span>}s,
               html
             )

      assert Regex.match?(
               ~r{phx-value-type="question"[^>]*>\s*Questions\s*<span[^>]*>1</span>}s,
               html
             )

      assert Regex.match?(
               ~r{phx-value-type="puzzle"[^>]*>\s*Puzzles\s*<span[^>]*>1</span>}s,
               html
             )
    end

    test "clicking a per-type chip narrows the visible notes", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r,
      comment: c,
      question: q,
      puzzle: p
    } do
      {:ok, view, html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # All three are present at mount (filter = :all).
      assert html =~ "id=\"margin-note-#{c.id}\""
      assert html =~ "id=\"margin-note-#{q.id}\""
      assert html =~ "id=\"margin-note-#{p.id}\""

      filtered =
        view
        |> element(~s(button[phx-value-type="question"]))
        |> render_click()

      # Only the question card remains; the others are stream-removed.
      assert filtered =~ "id=\"margin-note-#{q.id}\""
      refute filtered =~ "id=\"margin-note-#{c.id}\""
      refute filtered =~ "id=\"margin-note-#{p.id}\""
    end

    test "Margin header shows the filtered/total ratio", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, view, _} = conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      filtered =
        view
        |> element(~s(button[phx-value-type="puzzle"]))
        |> render_click()

      # "Margin · 1 of 3 notes" — span elements wrap the digits.
      assert Regex.match?(
               ~r{Margin · <span class="num">1</span>\s*of\s*<span class="num">3</span>\s*notes}s,
               filtered
             )
    end

    test "text_selected with type=question opens a question form and persists a question", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, view, _html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      open_html =
        render_hook(view, "text_selected", %{
          "text" => "the city of Diomira",
          "page" => 1,
          "rect" => %{"x" => 0.2, "y" => 0.4, "width" => 0.25, "height" => 0.04},
          "type" => "question"
        })

      # Form header reflects the chosen type.
      assert open_html =~ "New question · page"

      view
      |> form("#annotation-form", form: %{body: "is Diomira a city of memory?"})
      |> render_submit()

      [persisted] =
        Annotations.list_annotations!(
          actor: user,
          query: [
            filter: [resource_id: r.id, body: "is Diomira a city of memory?"]
          ]
        )

      assert persisted.type == :question
      assert persisted.color == "mint"
    end

    test "text_selected with type=puzzle persists a puzzle", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, view, _html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      render_hook(view, "text_selected", %{
        "text" => "the bridge between Despina and Anastasia",
        "page" => 1,
        "rect" => %{"x" => 0.1, "y" => 0.5, "width" => 0.4, "height" => 0.04},
        "type" => "puzzle"
      })

      view
      |> form("#annotation-form", form: %{body: "two cities, one passage — what's the trick?"})
      |> render_submit()

      [persisted] =
        Annotations.list_annotations!(
          actor: user,
          query: [
            filter: [
              resource_id: r.id,
              body: "two cities, one passage — what's the trick?"
            ]
          ]
        )

      assert persisted.type == :puzzle
      assert persisted.color == "lavender"
    end
  end

  describe "ResourceFileController" do
    test "members can fetch the PDF bytes", %{conn: conn, user: user, resource: r} do
      conn = conn |> sign_in(user) |> get(~p"/resources/#{r.id}/file")

      assert response(conn, 200) == @minimal_pdf
      assert get_resp_header(conn, "content-type") == ["application/pdf; charset=utf-8"]
    end

    test "non-members get 404", %{conn: conn, resource: r} do
      stranger = register_user("stranger-file@example.com")

      conn = conn |> sign_in(stranger) |> get(~p"/resources/#{r.id}/file")
      assert response(conn, 404)
    end
  end
end
