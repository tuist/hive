defmodule HiveWeb.SpecLive.IndexTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Auth
  alias Hive.Domains
  alias Hive.Projects
  alias Hive.Specs

  defp create_domain!(attrs) do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    attrs = Map.put_new(attrs, :project_id, project.id)
    {:ok, domain} = Domains.create_domain(attrs)
    domain
  end

  test "renders the empty state and OpenGraph metadata", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/specs")

    assert html =~ "Specs"
    assert html =~ "No specs yet"

    conn = get(conn, ~p"/specs")
    assert html_response(conn, 200) =~ ~s|property="og:image"|
  end

  test "lists specs and hides creation from guests", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")
    domain = create_domain!(%{name: "Hive"})

    {:ok, _spec} =
      Specs.create_spec(
        %{
          "title" => "GitHub sign-in",
          "body" => "Initial proposal.",
          "domain_ids" => [domain.id]
        },
        user
      )

    {:ok, _view, html} = live(Phoenix.ConnTest.build_conn(), ~p"/specs")

    assert html =~ "GitHub sign-in"
    assert html =~ "Hive"
    assert html =~ ~s(data-size="large")
    refute html =~ "New spec"

    {:ok, _view, html} = live(conn, ~p"/specs")
    assert html =~ "New spec"
  end

  test "shows all specs by default and filters through query params", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, _draft} =
      Specs.create_spec(%{"title" => "Draft proposal", "body" => "Initial proposal."}, user)

    {:ok, _approved} =
      Specs.create_spec(
        %{"title" => "Approved proposal", "body" => "Approved proposal.", "status" => "approved"},
        user
      )

    {:ok, _view, html} = live(conn, ~p"/specs")

    assert html =~ "Draft proposal"
    assert html =~ "Approved proposal"
    assert html =~ "Status"

    {:ok, _view, html} =
      live(conn, ~p"/specs?filter_status_op===&filter_status_val=draft")

    assert html =~ "Draft proposal"
    refute html =~ "Approved proposal"
    assert html =~ "Draft"

    {:ok, _view, html} =
      live(conn, ~p"/specs?filter_status_op===&filter_status_val=approved")

    assert html =~ "Approved proposal"
    refute html =~ "Draft proposal"
    assert html =~ "Approved"
  end

  test "hides private specs from contributors", %{conn: conn} do
    {_member_conn, member} = sign_in(conn, "member@tuist.dev")
    {contributor_conn, _contributor} = sign_in(conn, "contributor@example.com")

    {:ok, _public} =
      Specs.create_spec(
        %{"title" => "Public proposal", "body" => "Initial proposal.", "visibility" => "public"},
        member
      )

    {:ok, _private} =
      Specs.create_spec(
        %{
          "title" => "Private proposal",
          "body" => "Initial proposal.",
          "visibility" => "private"
        },
        member
      )

    stub(Auth, :member?, fn
      %{email: "member@tuist.dev"} -> true
      _user -> false
    end)

    {:ok, _view, html} = live(contributor_conn, ~p"/specs")

    assert html =~ "Public proposal"
    refute html =~ "Private proposal"
  end

  test "strips markdown from the spec preview text", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    body = """
    ## Why

    Tuist already runs `Tuist.Namespace.create_instance_with_ssh_connection/1`.

    ```elixir
    def hidden_in_preview, do: :ok
    ```
    """

    {:ok, _spec} = Specs.create_spec(%{"title" => "Schema spec", "body" => body}, user)

    {:ok, _view, html} = live(conn, ~p"/specs")

    refute html =~ "##"
    refute html =~ "```"
    refute html =~ "`Tuist.Namespace"
    assert html =~ "Tuist.Namespace.create_instance_with_ssh_connection/1"
  end

  test "shows public specs attached to private domains to contributors", %{conn: conn} do
    {_member_conn, member} = sign_in(conn, "member@tuist.dev")
    {contributor_conn, _contributor} = sign_in(conn, "contributor@example.com")
    private_domain = create_domain!(%{name: "Atlas", visibility: "private"})

    {:ok, _spec} =
      Specs.create_spec(
        %{
          "title" => "Public domain proposal",
          "body" => "Initial proposal.",
          "visibility" => "public",
          "domain_ids" => [private_domain.id]
        },
        member
      )

    stub(Auth, :member?, fn
      %{email: "member@tuist.dev"} -> true
      _user -> false
    end)

    {:ok, _view, html} = live(contributor_conn, ~p"/specs")

    assert html =~ "Public domain proposal"
  end

  test "renders the New activity badge when a spec changed since the user last viewed it",
       %{conn: conn} do
    {conn, reader} = sign_in(conn, "reader@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "Visible spec", "body" => "Initial proposal."}, reader)

    {:ok, _view, html} = live(conn, ~p"/specs")
    refute html =~ "New activity"

    :ok = Specs.mark_viewed(spec, reader)
    require Ecto.Query

    {1, _} =
      Hive.Repo.update_all(
        Ecto.Query.from(view in Specs.View,
          where: view.user_id == ^reader.id and view.spec_id == ^spec.id
        ),
        set: [last_viewed_at: ~U[2020-01-01 00:00:00.000000Z]]
      )

    {:ok, _comment} = Specs.add_comment(spec, %{"body" => "New note."}, reader)

    {:ok, _view, html} = live(conn, ~p"/specs")
    assert html =~ "New activity"
  end

  test "shows the sidebar new-activity dot when the user has unviewed updates",
       %{conn: conn} do
    {conn, reader} = sign_in(conn, "reader@example.com")

    {:ok, spec} =
      Specs.create_spec(%{"title" => "Sidebar dot spec", "body" => "Initial proposal."}, reader)

    {:ok, _view, html} = live(conn, ~p"/specs")
    refute html =~ ~s|data-new-activity="true"|

    :ok = Specs.mark_viewed(spec, reader)
    require Ecto.Query

    {1, _} =
      Hive.Repo.update_all(
        Ecto.Query.from(view in Specs.View,
          where: view.user_id == ^reader.id and view.spec_id == ^spec.id
        ),
        set: [last_viewed_at: ~U[2020-01-01 00:00:00.000000Z]]
      )

    {:ok, _spec} = Specs.update_spec(spec, %{"title" => "Edited"}, reader)

    {:ok, _view, html} = live(conn, ~p"/specs")
    assert html =~ ~s|data-new-activity="true"|
  end
end
