defmodule HiveWeb.SpecLive.ShowTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.Specs

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
    assert html_response(conn, 200) =~ ~s|property="og:image"|

    spec = Specs.get_spec!(spec.id)
    open_graph = HiveWeb.SpecLive.Show.open_graph(spec)
    assert open_graph.eyebrow == "Spec ##{spec.number}"
    assert open_graph.author == %{handle: "@alice", initials: "a"}
  end

  test "requires authentication to comment", %{conn: conn} do
    {_conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "GitHub sign-in", "body" => "Initial proposal."}, user)

    {:ok, _view, html} = live(Phoenix.ConnTest.build_conn(), ~p"/specs/#{spec.number}")

    assert html =~ "Sign in to comment"
    refute html =~ ~s|data-part="comment-form"|
  end

  test "blocks private specs from contributors", %{conn: conn} do
    {_member_conn, member} = sign_in(conn, "member@tuist.dev")
    {contributor_conn, _contributor} = sign_in(conn, "contributor@example.com")

    {:ok, spec} =
      Specs.create_spec(
        %{"title" => "Private spec", "body" => "Initial proposal.", "visibility" => "private"},
        member
      )

    stub(Auth, :member?, fn
      %{email: "member@tuist.dev"} -> true
      _user -> false
    end)

    assert {:error, {:redirect, %{to: "/specs"}}} =
             live(contributor_conn, ~p"/specs/#{spec.number}")
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
        spec: %{title: "GitHub OAuth", body: "Updated proposal.", status: "accepted"}
      )
      |> render_submit()

    {:ok, _view, html} = follow_redirect(result, conn)
    assert html =~ "GitHub OAuth"
    assert html =~ "Updated proposal."
    assert html =~ "Revision 2"
    assert html =~ "Revision 1"
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
end
