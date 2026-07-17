defmodule HiveWeb.Api.V1.SpecControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Specs

  @resource "http://www.example.com/api/v1"

  test "lists, searches, paginates, and gets visible specs", %{conn: conn} do
    {token, user} = mobile_access_token!("specs@example.com", "mobile", @resource)

    {:ok, wanted} =
      Specs.create_spec(
        %{"title" => "Mobile shell", "body" => "Build native tabs for the mobile application."},
        user
      )

    {:ok, _other} =
      Specs.create_spec(
        %{"title" => "Server work", "body" => "Keep the server contract documented."},
        user
      )

    list_conn =
      conn
      |> authorize(token)
      |> get(~p"/api/v1/specs?query=Mobile&page=1&page_size=1")

    response = json_response(list_conn, 200)

    assert [%{"number" => number, "title" => "Mobile shell", "revision" => 1}] =
             response["data"]

    assert number == wanted.number

    assert response["pagination"] == %{
             "page" => 1,
             "page_size" => 1,
             "total_count" => 1,
             "total_pages" => 1
           }

    show_conn = build_conn() |> authorize(token) |> get("/api/v1/specs/#{wanted.number}")
    assert json_response(show_conn, 200)["data"]["body"] =~ "native tabs"
  end

  test "returns not found for an unknown spec", %{conn: conn} do
    {token, _user} = mobile_access_token!("spec-missing@example.com", "mobile", @resource)

    response = conn |> authorize(token) |> get(~p"/api/v1/specs/999999") |> json_response(404)
    assert response["error"] == "not_found"
  end

  defp authorize(conn, token),
    do: put_req_header(conn, "authorization", "Bearer #{token.value}")
end
