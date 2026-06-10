defmodule HiveWeb.SpecLive.IndexTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Auth
  alias Hive.Products
  alias Hive.Specs

  test "renders the empty state and OpenGraph metadata", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/specs")

    assert html =~ "Specs"
    assert html =~ "No specs yet"

    conn = get(conn, ~p"/specs")
    assert html_response(conn, 200) =~ ~s|property="og:image"|
  end

  test "lists specs and hides creation from guests", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, _spec} =
      Specs.create_spec(%{"title" => "GitHub sign-in", "body" => "Initial proposal."}, user)

    {:ok, _view, html} = live(Phoenix.ConnTest.build_conn(), ~p"/specs")

    assert html =~ "GitHub sign-in"
    refute html =~ "New spec"

    {:ok, _view, html} = live(conn, ~p"/specs")
    assert html =~ "New spec"
  end

  test "defaults to draft specs and filters through query params", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, _draft} =
      Specs.create_spec(%{"title" => "Draft proposal", "body" => "Initial proposal."}, user)

    {:ok, _accepted} =
      Specs.create_spec(
        %{"title" => "Accepted proposal", "body" => "Accepted proposal.", "status" => "accepted"},
        user
      )

    {:ok, _view, html} = live(conn, ~p"/specs")

    assert html =~ "Draft proposal"
    refute html =~ "Accepted proposal"
    assert html =~ "Status"
    assert html =~ "Draft"

    {:ok, _view, html} =
      live(conn, ~p"/specs?filter_status_op===&filter_status_val=accepted")

    assert html =~ "Accepted proposal"
    refute html =~ "Draft proposal"
    assert html =~ "Accepted"
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

  test "shows public specs attached to private products to contributors", %{conn: conn} do
    {_member_conn, member} = sign_in(conn, "member@tuist.dev")
    {contributor_conn, _contributor} = sign_in(conn, "contributor@example.com")
    {:ok, private_product} = Products.create_product(%{name: "Atlas", visibility: "private"})

    {:ok, _spec} =
      Specs.create_spec(
        %{
          "title" => "Public product proposal",
          "body" => "Initial proposal.",
          "visibility" => "public",
          "product_ids" => [private_product.id]
        },
        member
      )

    stub(Auth, :member?, fn
      %{email: "member@tuist.dev"} -> true
      _user -> false
    end)

    {:ok, _view, html} = live(contributor_conn, ~p"/specs")

    assert html =~ "Public product proposal"
  end
end
