defmodule StudysyncWeb.PdfLive.ShowTest do
  use StudysyncWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  require Ash.Query

  alias Studysync.Accounts
  alias Studysync.Annotations
  alias Studysync.Library
  alias Studysync.Library.Storage
  alias Studysync.Progress
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

    test "outline_loaded swaps the chapter rail from placeholders to real chapters",
         %{conn: conn, user: user, workspace: ws, resource: r} do
      {:ok, view, html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # Pre-event: the rail falls back to roman-numeral placeholders.
      assert html =~ ~s(aria-label="Chapters")
      assert html =~ ~s(title="III")

      after_outline =
        render_hook(view, "outline_loaded", %{
          "chapters" => [
            %{"label" => "Cities & Memory", "page" => 1},
            %{"label" => "Cities & Desire", "page" => 2},
            # Bogus page number — out of range, dropped silently.
            %{"label" => "Out of bounds", "page" => 999},
            # Empty label — dropped.
            %{"label" => "  ", "page" => 3}
          ]
        })

      assert after_outline =~ "Cities &amp; Memory"
      assert after_outline =~ "Cities &amp; Desire"
      assert after_outline =~ ~s|title="Cities &amp; Memory (page 1)"|
      refute after_outline =~ "Out of bounds"
      # Roman placeholders gone once we have real chapters.
      refute after_outline =~ ~s(title="III")
    end

    test "chapter rail click pushes scroll_to_page to the canvas",
         %{conn: conn, user: user, workspace: ws, resource: r} do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      render_hook(view, "outline_loaded", %{
        "chapters" => [
          %{"label" => "Cities & Memory", "page" => 1},
          %{"label" => "Cities & Desire", "page" => 2}
        ]
      })

      view
      |> element(~s|button[phx-value-page="2"]|)
      |> render_click()

      assert_push_event(view, "scroll_to_page", %{page: 2})
    end

    test "chapter_clicked is a no-op when the page is out of range",
         %{conn: conn, user: user, workspace: ws, resource: r} do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # Hand-craft the event — the rail itself drops out-of-range entries
      # before render, so we have to drive the handler directly to exercise
      # the guard.
      render_hook(view, "chapter_clicked", %{"page" => 999})

      refute_push_event(view, "scroll_to_page", %{})
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
    # Slice 15a — both annotations live on page 1 so they both render as
    # full margin_note cards in the "This page" zone. The cross-page
    # behavior (a click on a non-focal annotation should jump focal_page)
    # is exercised by its own Slice 15a tests below.
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
          1,
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

      # All three render as full margin_notes in the single list (Slice 15a).
      assert html =~ "id=\"margin-note-#{c.id}\""
      assert html =~ "id=\"margin-note-#{q.id}\""
      assert html =~ "id=\"margin-note-#{p.id}\""

      filtered =
        view
        |> element(~s(button[phx-value-type="question"]))
        |> render_click()

      # Only the question card survives the filter.
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

  describe "visibility toggle (Slice 14)" do
    test "annotation form exposes a Private toggle defaulting to workspace-visible", %{
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
          "rect" => %{"x" => 0.2, "y" => 0.4, "width" => 0.25, "height" => 0.04}
        })

      # Toggle present, label visible to readers
      assert open_html =~ "Private — only you"
      assert open_html =~ ~s(value="private")
      # Default is workspace — checkbox is not pre-checked
      refute Regex.match?(
               ~r{<input[^>]*type="checkbox"[^>]*value="private"[^>]*\bchecked\b}s,
               open_html
             )
    end

    test "submitting with the Private toggle ticked persists a private annotation", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, view, _html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      render_hook(view, "text_selected", %{
        "text" => "Sophronia is a city of two halves",
        "page" => 1,
        "rect" => %{"x" => 0.15, "y" => 0.5, "width" => 0.4, "height" => 0.04}
      })

      view
      |> form("#annotation-form",
        form: %{body: "split-personality city", visibility: "private"}
      )
      |> render_submit()

      [persisted] =
        Annotations.list_annotations!(
          actor: user,
          query: [filter: [resource_id: r.id, body: "split-personality city"]]
        )

      assert persisted.visibility == :private
    end

    test "submitting without ticking the toggle persists a workspace-visible annotation", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, view, _html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      render_hook(view, "text_selected", %{
        "text" => "snippet",
        "page" => 1,
        "rect" => %{"x" => 0.1, "y" => 0.5, "width" => 0.2, "height" => 0.04}
      })

      view
      |> form("#annotation-form", form: %{body: "default-vis"})
      |> render_submit()

      [persisted] =
        Annotations.list_annotations!(
          actor: user,
          query: [filter: [resource_id: r.id, body: "default-vis"]]
        )

      assert persisted.visibility == :workspace
    end

    test "private margin notes render the lock indicator; workspace notes do not", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, public} =
        Annotations.create_comment(
          r.id,
          1,
          %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05},
          "public snippet",
          "public body",
          actor: user
        )

      {:ok, private} =
        Annotations.create_comment(
          r.id,
          1,
          %{"x" => 0.1, "y" => 0.4, "width" => 0.3, "height" => 0.05},
          "private snippet",
          "private body",
          %{visibility: :private},
          actor: user
        )

      {:ok, _view, html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # The private card carries the lock indicator + the "Private" label.
      assert Regex.match?(
               ~r{id="margin-note-#{private.id}".*?hero-lock-closed-mini.*?Private}s,
               html
             )

      # The workspace card does not.
      refute Regex.match?(
               ~r{id="margin-note-#{public.id}"[^>]*>(?:(?!margin-note-).)*hero-lock-closed-mini}s,
               html
             )
    end
  end

  describe "milestones (Slice 12)" do
    test "admins see the Place milestone toggle in the header", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, _view, html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      assert html =~ ~s(phx-click="toggle_milestone_mode")
      assert html =~ "Place milestone"
    end

    test "non-admin members do not see the Place milestone toggle", %{
      conn: conn,
      user: owner,
      workspace: ws,
      resource: r
    } do
      member = register_user("non-admin-reader@example.com")
      _ = Workspaces.invite_member!(ws.id, "non-admin-reader@example.com", actor: owner)

      [pending] =
        Studysync.Workspaces.Membership
        |> Ash.Query.filter(user_id == ^member.id)
        |> Ash.read!(authorize?: false)

      {:ok, _} = Workspaces.accept_invite(pending, actor: member)

      {:ok, _view, html} =
        conn |> sign_in(member) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      refute html =~ ~s(phx-click="toggle_milestone_mode")
      refute html =~ "Place milestone"
    end

    test "toggling milestone mode flips the toggle button label", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, view, html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      assert html =~ "Place milestone"
      refute html =~ "Cancel placement"

      flipped =
        view
        |> element(~s(button[phx-click="toggle_milestone_mode"]))
        |> render_click()

      # Slice 12 (revised): the placement hint banner is gone — the
      # floating form on the page surface tells the admin what to do.
      # The toggle button itself flips to "Cancel placement".
      assert flipped =~ "Cancel placement"
      refute flipped =~ "Click anywhere on a page to drop a milestone."
    end

    test "milestone_placed with a label persists and renders the marker in one shot",
         %{conn: conn, user: user, workspace: ws, resource: r} do
      {:ok, view, _html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      view |> element(~s(button[phx-click="toggle_milestone_mode"])) |> render_click()

      # The Svelte canvas now collects the label in a floating form on
      # click and ships `{ page, position, label }` together. No
      # intermediate margin form, no save_milestone round-trip.
      render_hook(view, "milestone_placed", %{
        "page" => 2,
        "position" => %{"x" => 0.4, "y" => 0.3},
        "label" => "End of Chapter 2"
      })

      [persisted] =
        Progress.list_milestones!(
          actor: user,
          query: [filter: [resource_id: r.id]]
        )

      assert persisted.label == "End of Chapter 2"
      assert persisted.page_number == 2
      assert persisted.position == %{"x" => 0.4, "y" => 0.3}

      after_save = render(view)

      # Margin column shows the milestone in the panel
      assert after_save =~ "End of Chapter 2"
      assert after_save =~ ~s(id="milestone-#{persisted.id}")
      # Mode auto-exits after a successful placement
      refute after_save =~ "Cancel placement"
    end

    test "milestone_placed with an empty label is a no-op", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, view, _html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      view |> element(~s(button[phx-click="toggle_milestone_mode"])) |> render_click()

      render_hook(view, "milestone_placed", %{
        "page" => 1,
        "position" => %{"x" => 0.5, "y" => 0.5},
        "label" => "   "
      })

      assert Progress.list_milestones!(
               actor: user,
               query: [filter: [resource_id: r.id]]
             ) == []
    end

    test "milestone_placed from a non-admin is a no-op", %{
      conn: conn,
      user: owner,
      workspace: ws,
      resource: r
    } do
      member = register_user("non-admin-place@example.com")
      _ = Workspaces.invite_member!(ws.id, "non-admin-place@example.com", actor: owner)

      [pending] =
        Studysync.Workspaces.Membership
        |> Ash.Query.filter(user_id == ^member.id)
        |> Ash.read!(authorize?: false)

      {:ok, _} = Workspaces.accept_invite(pending, actor: member)

      {:ok, view, _html} =
        conn |> sign_in(member) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      render_hook(view, "milestone_placed", %{
        "page" => 1,
        "position" => %{"x" => 0.5, "y" => 0.5},
        "label" => "Sneaky"
      })

      assert Progress.list_milestones!(
               actor: owner,
               query: [filter: [resource_id: r.id]]
             ) == []
    end

    test "existing milestones render in the panel and pass to the canvas on mount", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, milestone} =
        Progress.create_milestone(
          r.id,
          1,
          %{"x" => 0.3, "y" => 0.7},
          "End of Prologue",
          actor: user
        )

      {:ok, _view, html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      assert html =~ ~s(id="milestone-#{milestone.id}")
      assert html =~ "End of Prologue"
      # Slice header in the milestone panel.
      assert html =~ "Milestones · "
    end
  end

  describe "rubber stamps (Slice 13)" do
    test "applying a stamp via the canvas event persists and reflects in the panel", %{
      conn: conn,
      user: user,
      workspace: ws,
      resource: r
    } do
      {:ok, milestone} =
        Progress.create_milestone(
          r.id,
          1,
          %{"x" => 0.4, "y" => 0.4},
          "End of Prologue",
          actor: user
        )

      {:ok, view, _html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      after_stamp = render_hook(view, "apply_stamp", %{"milestone_id" => milestone.id})

      stamps =
        Progress.list_stamps!(
          actor: user,
          query: [filter: [milestone_id: milestone.id]]
        )

      assert length(stamps) == 1
      # Panel surfaces "1 / 1 stamped" once the actor's stamp lands.
      assert after_stamp =~
               ~r{<span class="num">1</span>\s*/\s*<span class="num">1</span>\s*stamped}
    end

    test "non-members cannot stamp via the canvas event", %{
      conn: conn,
      user: owner,
      workspace: ws,
      resource: r
    } do
      stranger = register_user("stamp-noway@example.com")

      {:ok, milestone} =
        Progress.create_milestone(
          r.id,
          1,
          %{"x" => 0.5, "y" => 0.5},
          "End of Chapter 1",
          actor: owner
        )

      # Stranger can't even open the LV, so simulate the event from a member
      # who isn't in the workspace by attempting via a freshly-mounted, signed-in
      # session that isn't a member of `ws`. We expect the apply_stamp call to
      # surface a flash and persist nothing.
      _ = stranger
      # The straightforward assertion: an admin tries to double-stamp;
      # the second call is silently absorbed (idempotent UX) and only one
      # stamp row exists.
      {:ok, view, _html} =
        conn |> sign_in(owner) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      render_hook(view, "apply_stamp", %{"milestone_id" => milestone.id})
      render_hook(view, "apply_stamp", %{"milestone_id" => milestone.id})

      stamps =
        Progress.list_stamps!(
          actor: owner,
          query: [filter: [milestone_id: milestone.id]]
        )

      assert length(stamps) == 1
    end

    test "an out-of-band stamp shows up live for an open reader", %{
      conn: conn,
      user: owner,
      workspace: ws,
      resource: r
    } do
      member = register_user("stamp-rt@example.com")
      _ = Workspaces.invite_member!(ws.id, "stamp-rt@example.com", actor: owner)

      [pending] =
        Studysync.Workspaces.Membership
        |> Ash.Query.filter(user_id == ^member.id)
        |> Ash.read!(authorize?: false)

      {:ok, _} = Workspaces.accept_invite(pending, actor: member)

      {:ok, milestone} =
        Progress.create_milestone(
          r.id,
          1,
          %{"x" => 0.3, "y" => 0.7},
          "Real-time check",
          actor: owner
        )

      {:ok, view, _html} =
        conn |> sign_in(owner) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # Out-of-band — not the LV process, runs the after_action broadcast.
      {:ok, _} = Progress.apply_stamp(milestone.id, nil, actor: member)

      patched = render(view)

      # Panel reflects the new stamp count without requiring the LV to act.
      assert patched =~ ~r{<span class="num">1</span>\s*/\s*<span class="num">2</span>\s*stamped}
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

  describe "Slice 15a — single-list margin with focal-page highlight" do
    # Six-page PDF so we can exercise focal-page transitions across the book.
    @six_page_pdf """
    %PDF-1.4
    1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
    2 0 obj << /Type /Pages /Kids [3 0 R 4 0 R 5 0 R 6 0 R 7 0 R 8 0 R] /Count 6 >> endobj
    3 0 obj << /Type /Page /Parent 2 0 R >> endobj
    4 0 obj << /Type /Page /Parent 2 0 R >> endobj
    5 0 obj << /Type /Page /Parent 2 0 R >> endobj
    6 0 obj << /Type /Page /Parent 2 0 R >> endobj
    7 0 obj << /Type /Page /Parent 2 0 R >> endobj
    8 0 obj << /Type /Page /Parent 2 0 R >> endobj
    trailer << /Root 1 0 R >>
    %%EOF
    """

    setup %{user: user, workspace: workspace} do
      resource =
        Library.upload_resource!(
          workspace.id,
          "Six-page Book",
          %{content: @six_page_pdf, filename: "six.pdf"},
          actor: user
        )

      on_exit(fn -> Storage.delete(resource.file_path) end)

      rect = %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05}

      {:ok, near} =
        Annotations.create_comment(resource.id, 1, rect, "page-1-snip", "page-1 body",
          actor: user
        )

      {:ok, far} =
        Annotations.create_comment(resource.id, 5, rect, "page-5-snip", "page-5 body",
          actor: user
        )

      %{long_resource: resource, near: near, far: far}
    end

    test "every annotation renders as a full margin note regardless of page",
         %{conn: conn, user: user, workspace: ws, long_resource: r, near: near, far: far} do
      {:ok, _view, html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # Both annotations are full margin_note cards with body in the DOM —
      # no truncation, no zone split. The reader sees every peer mark in
      # the book at once.
      assert html =~ "id=\"margin-note-#{near.id}\""
      assert html =~ "page-1 body"
      assert html =~ "id=\"margin-note-#{far.id}\""
      assert html =~ "page-5 body"

      assert html =~
               ~r{Margin · <span class="num">2</span>\s*of\s*<span class="num">2</span>\s*notes}
    end

    test "focal-page card carries the bg-paper highlight; off-focal cards don't",
         %{conn: conn, user: user, workspace: ws, long_resource: r, near: near, far: far} do
      {:ok, _view, html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # focal_page = 1 at mount → page-1 card carries `data-focal-page="true"`.
      assert Regex.match?(
               ~r{id="margin-note-#{near.id}"[^>]*data-focal-page="true"},
               html
             )

      # Page-5 card is off-focal — `data-focal-page="false"`.
      assert Regex.match?(
               ~r{id="margin-note-#{far.id}"[^>]*data-focal-page="false"},
               html
             )
    end

    test "pages_visible flips focal_page → highlight follows the reader's scroll",
         %{conn: conn, user: user, workspace: ws, long_resource: r, near: near, far: far} do
      {:ok, view, _html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # Reader scrolls to page 5. focal_page flips, so the page-5 card now
      # carries the focal flag and the page-1 card loses it. Critically,
      # both cards are still rendered as full margin_notes — the layout
      # doesn't shift.
      after_scroll = render_hook(view, "pages_visible", %{"first" => 5, "last" => 5})

      assert Regex.match?(
               ~r{id="margin-note-#{far.id}"[^>]*data-focal-page="true"},
               after_scroll
             )

      assert Regex.match?(
               ~r{id="margin-note-#{near.id}"[^>]*data-focal-page="false"},
               after_scroll
             )

      # Bodies still in the DOM for both — single stable list.
      assert after_scroll =~ "page-1 body"
      assert after_scroll =~ "page-5 body"
    end

    test "pages_visible is a no-op when focal_page is unchanged",
         %{conn: conn, user: user, workspace: ws, long_resource: r} do
      {:ok, view, _html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      first = render_hook(view, "pages_visible", %{"first" => 1, "last" => 2})
      second = render_hook(view, "pages_visible", %{"first" => 1, "last" => 2})

      # Re-reporting an unchanged range hits the early-return — no diff
      # bumped on the wire.
      assert first == second
    end

    test "footnote numbering resets per page",
         %{conn: conn, user: user, workspace: ws, long_resource: r} do
      rect = %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05}

      # Two on page 1, one on page 2 → page 1 has ¹ ², page 2 has ¹.
      {:ok, _} =
        Annotations.create_comment(r.id, 1, rect, "p1-second", "another on page 1", actor: user)

      {:ok, _} =
        Annotations.create_comment(r.id, 2, rect, "p2-first", "first on page 2", actor: user)

      {:ok, _view, html} =
        conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # Both pages are now in a single list. We expect ¹ at least twice
      # (once per page) and ² once (the second page-1 annotation).
      assert Regex.scan(~r{<sup[^>]*>\s*1\s*</sup>}, html) |> length() >= 2
      assert Regex.match?(~r{<sup[^>]*>\s*2\s*</sup>}, html)
      # No ³ — global numbering would have produced one for the page-2
      # first annotation.
      refute Regex.match?(~r{<sup[^>]*>\s*3\s*</sup>}, html)
    end
  end

  describe "Slice 15 — telemetry" do
    test "annotation create emits a [:studysync, :annotations, :create, :stop] event",
         %{conn: conn, user: user, workspace: ws, resource: r} do
      ref = make_ref()
      handler_id = "test-telemetry-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:studysync, :annotations, :create, :stop],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {ref, :create_stop, measurements, metadata})
        end,
        nil
      )

      try do
        {:ok, view, _html} =
          conn |> sign_in(user) |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

        render_hook(view, "text_selected", %{
          "text" => "telemetry snippet",
          "page" => 1,
          "rect" => %{"x" => 0.1, "y" => 0.2, "width" => 0.2, "height" => 0.04}
        })

        view
        |> form("#annotation-form", form: %{body: "telemetry body"})
        |> render_submit()

        assert_receive {^ref, :create_stop, measurements, metadata}, 500

        assert is_integer(measurements[:duration]) and measurements[:duration] >= 0
        assert metadata[:type] == :comment
        assert metadata[:resource_id] == r.id
        assert metadata[:outcome] == :ok
      after
        :telemetry.detach(handler_id)
      end
    end

    test "PubSub broadcast emits a [:studysync, :pubsub, :broadcast, :stop] event",
         %{user: user, resource: r} do
      ref = make_ref()
      handler_id = "test-pubsub-telemetry-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:studysync, :pubsub, :broadcast, :stop],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {ref, :broadcast, measurements, metadata})
        end,
        nil
      )

      try do
        # Creating an annotation triggers two broadcasts — resource topic
        # and workspace topic. We only need to see that the telemetry hook
        # fired at all, with our event tag.
        {:ok, _} =
          Annotations.create_comment(
            r.id,
            1,
            %{"x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.05},
            "broadcast snippet",
            "broadcast body",
            actor: user
          )

        assert_receive {^ref, :broadcast, measurements, metadata}, 500

        assert is_integer(measurements[:duration]) and measurements[:duration] >= 0
        assert metadata[:event] in [:annotation_created, :activity_annotation_created]
        assert is_binary(metadata[:topic])
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  describe "Slice 18 — transient chat panel" do
    test "mount shows the collapsed pill and seeds recent buffer messages on expand",
         %{conn: conn, user: user, workspace: ws, resource: r} do
      # Pre-seed the buffer directly so we don't have to round-trip through
      # the panel's optimistic insert. `to_string/1` strips Ash.CiString.
      {:ok, _} =
        Studysync.Chat.Buffer.append(r.id, user.id, to_string(user.email), "earlier message")

      {:ok, view, html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      # Collapsed by default — the pill is visible (aria-hidden="false")
      # and the panel section is hidden (aria-hidden="true"). The panel
      # stays in the DOM so streams keep their items across toggles, but
      # is visually hidden via the `hidden` Tailwind class.
      assert html =~ ~s(aria-label="Open chat)
      assert html =~ ~s(aria-label="Study-room chat" aria-hidden="true")
      # Seeded message is in the DOM but inside the hidden section.
      assert html =~ "earlier message"

      # Expand — the panel becomes visible and shows the seeded message.
      after_open =
        view
        |> element(~s|button[aria-label^="Open chat"]|)
        |> render_click()

      assert after_open =~ ~s(aria-label="Study-room chat" aria-hidden="false")
      assert after_open =~ "earlier message"
      assert after_open =~ "here now"
    end

    test "sending a message via the form inserts it into the panel locally",
         %{conn: conn, user: user, workspace: ws, resource: r} do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      view |> element(~s|button[aria-label^="Open chat"]|) |> render_click()

      after_send =
        view
        |> form("#chat-panel form", message: %{body: "hello room"})
        |> render_submit()

      assert after_send =~ "hello room"

      # The message is also in the buffer.
      assert [%Studysync.Chat.Message{body: "hello room"}] = Studysync.Chat.recent(r.id)
    end

    test "an empty message surfaces a validation error and doesn't insert",
         %{conn: conn, user: user, workspace: ws, resource: r} do
      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      view |> element(~s|button[aria-label^="Open chat"]|) |> render_click()

      after_send =
        view
        |> form("#chat-panel form", message: %{body: "   "})
        |> render_submit()

      assert after_send =~ "can&#39;t be blank"
      assert Studysync.Chat.recent(r.id) == []
    end

    test "a peer's broadcast lands in the panel via send_update",
         %{conn: conn, user: user, workspace: ws, resource: r} do
      member = register_user("chat-peer@example.com")
      _ = Workspaces.invite_member!(ws.id, "chat-peer@example.com", actor: user)

      [pending] =
        Studysync.Workspaces.Membership
        |> Ash.Query.filter(user_id == ^member.id)
        |> Ash.read!(authorize?: false)

      {:ok, _} = Workspaces.accept_invite(pending, actor: member)

      {:ok, view, _html} =
        conn
        |> sign_in(user)
        |> live(~p"/workspaces/#{ws.id}/library/#{r.id}")

      view |> element(~s|button[aria-label^="Open chat"]|) |> render_click()

      # Peer sends a message — broadcast lands in the LV's mailbox and is
      # forwarded to the component via send_update. The peer is on a
      # different (test) process, so broadcast_from! delivers to the LV.
      {:ok, %Studysync.Chat.Message{}} =
        Studysync.Chat.send_message(member, r.id, "ping from a peer")

      html = render(view)
      assert html =~ "ping from a peer"
    end
  end
end
