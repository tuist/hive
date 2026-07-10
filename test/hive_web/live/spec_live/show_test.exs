defmodule HiveWeb.SpecLive.ShowTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.Domains
  alias Hive.Projects
  alias Hive.Repo
  alias Hive.Slack.Installation
  alias Hive.Specs
  alias Hive.Specs.RevisionSummaries

  defp create_domain!(attrs) do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    attrs = Map.put_new(attrs, :project_id, project.id)
    {:ok, domain} = Domains.create_domain(attrs)
    domain
  end

  defp slack_review_notifications! do
    suffix = System.unique_integer([:positive])

    {:ok, _installation} =
      %Installation{}
      |> Installation.changeset(%{
        team_id: "T#{suffix}",
        team_name: "Workspace #{suffix}",
        bot_token: "xoxb-#{suffix}",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        notification_channel_id: "C#{suffix}",
        notification_events: ["spec.review.requested"]
      })
      |> Repo.insert()
  end

  test "renders a spec and OpenGraph metadata", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "GitHub sign-in",
          "body" =>
            "## Proposal\n\nInitial **proposal**.\n\nAcceptance criteria:\n- First criterion"
        },
        user
      )

    {:ok, _view, html} = live(conn, ~p"/specs/#{spec.number}")

    assert html =~ "GitHub sign-in"
    assert html =~ "<h3>Proposal</h3>"
    assert html =~ "Initial <strong>proposal</strong>."
    assert html =~ "<p>Acceptance criteria:</p>"
    assert html =~ "<li>First criterion</li>"
    assert html =~ "Draft history"
    assert html =~ "Revision 1"

    conn = get(conn, ~p"/specs/#{spec.number}")
    response = html_response(conn, 200)

    assert response =~ ~s|>GitHub sign-in · Hive</title>|
    assert response =~ ~s(property="og:title" content="GitHub sign-in | Hive")
    assert response =~ ~s(/specs/#{spec.number}")
    assert response =~ ~s|property="og:image"|
    assert response =~ ~s(/open-graph/card.jpg?token=)

    spec = Specs.get_spec!(spec.id)
    open_graph = HiveWeb.SpecLive.Show.open_graph(spec)
    assert open_graph.section_label == "Spec ##{spec.number}"
    assert open_graph.author == %{handle: "@alice", initials: "a"}
  end

  test "renders public spec head metadata for anonymous visitors", %{conn: conn} do
    {_conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Move object storage into the cluster",
          "body" => "Use Rook and Ceph to provide object storage from the Kubernetes cluster.",
          "summary" => "Move object storage to Kubernetes with Rook and Ceph."
        },
        user
      )

    conn = Phoenix.ConnTest.build_conn() |> get(~p"/specs/#{spec.number}")
    response = html_response(conn, 200)

    assert response =~ ~s|>Move object storage into the cluster · Hive</title>|

    assert response =~
             ~s(property="og:title" content="Move object storage into the cluster | Hive")

    assert response =~
             ~s(property="og:description" content="Move object storage to Kubernetes with Rook and Ceph.")

    assert response =~ ~s(property="og:image")
    assert response =~ ~s(/open-graph/card.jpg?token=)
  end

  test "requires authentication to comment", %{conn: conn} do
    {_conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "GitHub sign-in", "body" => "Initial proposal."}, user)

    {:ok, _view, html} = live(Phoenix.ConnTest.build_conn(), ~p"/specs/#{spec.number}")

    assert html =~ "Sign in to comment"
    assert html =~ ~s(href="/login?return_to=%2Fspecs%2F#{spec.number}")
    refute html =~ ~s|data-part="comment-form"|
  end

  test "blocks private specs from contributors", %{conn: conn} do
    {_member_conn, member} = sign_in(conn, "member@tuist.dev")
    {contributor_conn, _contributor} = sign_in(conn, "contributor@example.com")

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Private spec",
          "body" => "Initial proposal.",
          "visibility_override" => "private"
        },
        member
      )

    stub(Auth, :member?, fn
      %{email: "member@tuist.dev"} -> true
      _user -> false
    end)

    assert {:error, {:redirect, %{to: "/specs"}}} =
             live(contributor_conn, ~p"/specs/#{spec.number}")
  end

  test "shows specs from public projects even when attached to private domains", %{conn: conn} do
    {_member_conn, member} = sign_in(conn, "member@tuist.dev")
    {contributor_conn, _contributor} = sign_in(conn, "contributor@example.com")
    {:ok, project} = Projects.create_project(%{name: "Atlas app", visibility: "public"})
    domain = create_domain!(%{name: "Atlas", project_id: project.id, visibility: "private"})

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Public domain spec",
          "body" => "Initial proposal.",
          "project_id" => project.id,
          "domain_ids" => [domain.id]
        },
        member
      )

    stub(Auth, :member?, fn
      %{email: "member@tuist.dev"} -> true
      _user -> false
    end)

    assert {:ok, _view, html} = live(contributor_conn, ~p"/specs/#{spec.number}")
    assert html =~ "Public domain spec"
  end

  test "labels specs from public projects as public for members", %{conn: conn} do
    {conn, member} = sign_in(conn, "member@tuist.dev")
    {:ok, project} = Projects.create_project(%{name: "Atlas app", visibility: "public"})
    domain = create_domain!(%{name: "Atlas", project_id: project.id, visibility: "private"})

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Public domain spec",
          "body" => "Initial proposal.",
          "project_id" => project.id,
          "domain_ids" => [domain.id]
        },
        member
      )

    {:ok, _view, html} = live(conn, ~p"/specs/#{spec.number}")

    assert html =~ "Atlas app · Public · Created directly"
  end

  test "allows signed-in users to comment", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "GitHub sign-in", "body" => "Initial proposal."}, user)

    {:ok, view, _html} = live(conn, ~p"/specs/#{spec.number}")

    html =
      view
      |> form("form[data-part='comment-form']",
        comment: %{body: "This would **help** our team."}
      )
      |> render_submit()

    assert html =~ "alice@example.com"
    assert html =~ "This would <strong>help</strong> our team."
    assert html =~ ~s|href="#comment-|
    assert html =~ ~s|aria-label="Permalink to comment"|
  end

  test "renders mention autocomplete suggestions for spec participants", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "GitHub sign-in", "body" => "Initial proposal."}, user)

    {:ok, bob} =
      Accounts.upsert_from_auth(%{
        email: "bob@example.com",
        name: "Bob Example",
        provider: "test",
        provider_uid: "bob@example.com"
      })

    {:ok, _comment} = Specs.add_comment(spec, %{"body" => "Worth doing."}, bob)

    {:ok, _view, html} = live(conn, ~p"/specs/#{spec.number}")

    assert html =~ ~s|phx-hook="MentionAutocomplete"|
    assert html =~ ~s|&quot;token&quot;:&quot;alice&quot;|
    assert html =~ ~s|&quot;token&quot;:&quot;bob&quot;|
    assert html =~ "Bob Example"
    assert html =~ "bob@example.com"
  end

  test "allows comment authors to edit their comments", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "GitHub sign-in", "body" => "Initial proposal."}, user)

    {:ok, comment} = Specs.add_comment(spec, %{"body" => "Rendered without line breaks."}, user)
    {:ok, view, html} = live(conn, ~p"/specs/#{spec.number}")

    assert html =~ ~s|aria-label="Edit comment"|

    html = render_click(view, "edit_comment", %{"id" => comment.id})

    assert html =~ "Save comment"
    assert html =~ "Rendered without line breaks."

    html =
      view
      |> form("form[data-part='comment-edit-form']",
        comment_edit: %{body: "Properly formatted now, thanks @marek."}
      )
      |> render_submit()

    assert html =~ "Properly formatted now, thanks "
    assert html =~ ~s|<span data-part="mention" data-mention="@marek">@marek</span>|
    refute html =~ "Rendered without line breaks."
  end

  test "allows comment authors to delete their comments", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "GitHub sign-in", "body" => "Initial proposal."}, user)

    {:ok, comment} = Specs.add_comment(spec, %{"body" => "Comment to remove."}, user)
    {:ok, view, html} = live(conn, ~p"/specs/#{spec.number}")

    assert html =~ ~s|aria-label="Delete comment"|
    assert html =~ ~s|id="delete-comment-modal-#{comment.id}"|
    assert html =~ "Delete comment?"
    assert html =~ "Deleting this comment will permanently remove it from the spec discussion"
    refute html =~ ~s|data-confirm="Delete this comment?"|
    assert html =~ "Comment to remove."

    html = render_click(view, "delete_comment", %{"id" => comment.id})

    assert html =~ "Comment deleted."
    assert html =~ "No comments yet"
    refute html =~ "Comment to remove."

    spec = Specs.get_spec!(spec.id)
    assert spec.comments == []
  end

  test "hides comment edit and delete controls from other users", %{conn: conn} do
    {_author_conn, author} = sign_in(conn, "alice@example.com")
    {conn, _other_user} = sign_in(conn, "bob@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "GitHub sign-in", "body" => "Initial proposal."}, author)

    {:ok, comment} = Specs.add_comment(spec, %{"body" => "Author note."}, author)
    {:ok, view, html} = live(conn, ~p"/specs/#{spec.number}")

    refute html =~ ~s|aria-label="Edit comment"|
    refute html =~ ~s|aria-label="Delete comment"|
    refute html =~ "Delete comment?"

    html = render_click(view, "edit_comment", %{"id" => comment.id})

    refute html =~ "Save comment"

    html = render_click(view, "delete_comment", %{"id" => comment.id})

    assert html =~ "Only the comment author can delete this comment."

    spec = Specs.get_spec!(spec.id)
    assert Enum.map(spec.comments, & &1.body) == ["Author note."]
  end

  test "renders author avatars with GitHub and Gravatar sources", %{conn: conn} do
    {_member_conn, user} = sign_in(conn, "alice@example.com")

    {:ok, github_user} =
      Accounts.upsert_from_auth(%{
        email: "octo@example.com",
        provider: "github",
        provider_uid: "12345"
      })

    {:ok, spec} =
      Specs.create_spec(%{"title" => "GitHub sign-in", "body" => "Initial proposal."}, user)

    {:ok, _comment} = Specs.add_comment(spec, %{"body" => "From GitHub."}, github_user)
    {:ok, _comment} = Specs.add_comment(spec, %{"body" => "From email."}, user)

    {:ok, _view, html} = live(conn, ~p"/specs/#{spec.number}")

    assert html =~ "https://avatars.githubusercontent.com/u/12345?v=4"
    assert html =~ "https://www.gravatar.com/avatar/"
  end

  test "lets members edit specs", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "GitHub sign-in", "body" => "Initial proposal."}, user)

    {:ok, view, _html} = live(conn, ~p"/specs/#{spec.number}/edit")

    result =
      view
      |> form("form[data-part='form']",
        spec: %{title: "GitHub OAuth", body: "Updated proposal.", status: "approved"}
      )
      |> render_submit()

    {:ok, _view, html} = follow_redirect(result, conn)
    assert html =~ "GitHub OAuth"
    assert html =~ "Updated proposal."
    assert html =~ "Revision 2"
    assert html =~ "Revision 1"
  end

  test "lets members flip the spec status from the show header", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "Memory subsystem", "body" => "Initial proposal."}, user)

    {:ok, view, _html} = live(conn, ~p"/specs/#{spec.number}")

    html = render_click(view, "set_status", %{"status" => "approved"})

    assert html =~ "Approved"

    refreshed = Specs.get_spec!(spec.id)
    assert refreshed.status == :approved
    assert Enum.any?(refreshed.revisions, &(&1.status == :approved))
  end

  test "lets members request review from the show header", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")
    slack_review_notifications!()

    {:ok, spec} =
      Specs.create_spec(%{"title" => "Memory subsystem", "body" => "Initial proposal."}, user)

    {:ok, view, html} = live(conn, ~p"/specs/#{spec.number}")

    assert html =~ "Ask for review"

    html = render_click(view, "request_review")

    assert html =~ "Review request posted to Slack."
  end

  test "rejects status changes from non-members", %{conn: conn} do
    {_member_conn, member} = sign_in(conn, "member@tuist.dev")
    {contributor_conn, _contributor} = sign_in(conn, "contributor@example.com")

    {:ok, spec} =
      Specs.create_spec(
        %{"title" => "Memory subsystem", "body" => "Initial proposal."},
        member
      )

    stub(Auth, :member?, fn
      %{email: "member@tuist.dev"} -> true
      _user -> false
    end)

    {:ok, view, _html} = live(contributor_conn, ~p"/specs/#{spec.number}")

    render_click(view, "set_status", %{"status" => "approved"})

    refreshed = Specs.get_spec!(spec.id)
    assert refreshed.status == :draft
    refute Enum.any?(refreshed.revisions, &(&1.status == :approved))
  end

  test "expands revision rows to show a change summary", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "GitHub sign-in",
          "body" => "Keep source URL visible.\nImport comments."
        },
        user
      )

    {:ok, spec} =
      Specs.update_spec(
        Specs.get_spec!(spec.id),
        %{
          "title" => "GitHub sign-in",
          "body" => "Keep source URL visible.\nImport discussion comments.\nSkip duplicates.",
          "lock_version" => spec.lock_version
        },
        user
      )

    spec = Specs.get_spec!(spec.id)
    revision = Enum.find(spec.revisions, &(&1.revision == 2))

    {:ok, view, _html} = live(conn, ~p"/specs/#{spec.number}")

    html = render_click(view, "toggle-expand", %{"row-key" => "revision-#{revision.id}"})

    assert html =~ "Revision 2 summary"
    assert html =~ "This revision updated the proposal body with 2 additions and 1 removal."
    refute html =~ ~s|data-type="removed"|
    refute html =~ "<code>Import comments.</code>"
  end

  test "prefers the agent-written summary when present", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(
        %{"title" => "GitHub sign-in", "body" => "Keep source URL visible."},
        user
      )

    {:ok, spec} =
      Specs.update_spec(
        Specs.get_spec!(spec.id),
        %{
          "title" => "GitHub sign-in",
          "body" => "Keep source URL visible.\nImport discussion comments.",
          "lock_version" => spec.lock_version
        },
        user
      )

    spec = Specs.get_spec!(spec.id)
    revision = Enum.find(spec.revisions, &(&1.revision == 2))

    revision
    |> Hive.Specs.Revision.summary_changeset("Added a discussion import step.")
    |> Hive.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/specs/#{spec.number}")

    html = render_click(view, "toggle-expand", %{"row-key" => "revision-#{revision.id}"})

    assert html =~ "Added a discussion import step."
    refute html =~ "This revision updated the proposal body"
  end

  test "records a view for the signed-in user", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    assert Hive.Repo.all(Specs.View) == []

    {:ok, _view, _html} = live(conn, ~p"/specs/#{spec.number}")

    [view] = Hive.Repo.all(Specs.View)
    assert view.spec_id == spec.id
    assert view.user_id == user.id
  end

  test "does not record a view for anonymous visitors" do
    {_, user} = sign_in(Phoenix.ConnTest.build_conn(), "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    {:ok, _view, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/specs/#{spec.number}")

    assert Hive.Repo.all(Specs.View) == []
  end

  test "does not show a new-activity indicator on a first visit", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    {:ok, _view, html} = live(conn, ~p"/specs/#{spec.number}")
    refute html =~ ~s|>New activity<|
    refute html =~ ~s|>New<|
  end

  test "shows the new-activity header text and per-comment tag after activity since last visit",
       %{conn: conn} do
    {author_conn, author} = sign_in(conn, "author@example.com")
    {reader_conn, reader} = sign_in(conn, "reader@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "Visible", "body" => "Initial proposal."}, author)

    {:ok, old_comment} =
      Specs.add_comment(spec, %{"body" => "Previously seen note."}, author)

    {:ok, _view, _html} = live(reader_conn, ~p"/specs/#{spec.number}")
    require Ecto.Query

    {1, _} =
      Hive.Repo.update_all(
        Ecto.Query.from(view in Specs.View,
          where: view.user_id == ^reader.id and view.spec_id == ^spec.id
        ),
        set: [last_viewed_at: ~U[2020-01-01 00:00:00.000000Z]]
      )

    {:ok, fresh_comment} =
      Specs.add_comment(spec, %{"body" => "Fresh note for the reader."}, author)

    {:ok, _view, html} = live(reader_conn, ~p"/specs/#{spec.number}")
    assert html =~ "New activity"
    assert html =~ "comment-#{fresh_comment.id}"
    refute html =~ ~s|id="comment-#{old_comment.id}"[^>]*>\\s*<.*>New<|

    {:ok, _view, html2} = live(author_conn, ~p"/specs/#{spec.number}")
    refute html2 =~ "New activity"
  end

  test "refreshes expanded revision rows when the agent summary is stored", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(
        %{"title" => "GitHub sign-in", "body" => "Keep source URL visible."},
        user
      )

    {:ok, spec} =
      Specs.update_spec(
        Specs.get_spec!(spec.id),
        %{
          "title" => "GitHub sign-in",
          "body" => "Keep source URL visible.\nImport discussion comments.",
          "lock_version" => spec.lock_version
        },
        user
      )

    spec = Specs.get_spec!(spec.id)
    revision = Enum.find(spec.revisions, &(&1.revision == 2))

    {:ok, view, _html} = live(conn, ~p"/specs/#{spec.number}")

    html = render_click(view, "toggle-expand", %{"row-key" => "revision-#{revision.id}"})
    assert html =~ "This revision expanded the proposal body with 1 addition."

    runner = fn _input ->
      {:ok, %{summary: "Added discussion comment importing to the proposal."}}
    end

    assert {:ok, _updated} = RevisionSummaries.summarize(revision.id, runner: runner)
    :sys.get_state(view.pid)

    html = render(view)
    assert html =~ "Added discussion comment importing to the proposal."
    refute html =~ "This revision expanded the proposal body with 1 addition."
  end
end
