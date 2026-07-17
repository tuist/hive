defmodule HiveWeb.Api.V1.ForageControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Forage

  @resource "http://www.example.com/api/v1"

  test "lists, searches, and gets visible forage items", %{conn: conn} do
    {token, user} = mobile_access_token!("forage@example.com", "mobile", @resource)

    {:ok, item} =
      Forage.create_feature_request(
        %{
          "title" => "Native navigation",
          "description" => "Expose forage items in the mobile application."
        },
        user
      )

    list_conn = conn |> authorize(token) |> get(~p"/api/v1/forage?query=Native")
    response = json_response(list_conn, 200)

    assert [%{"id" => item_id, "title" => "Native navigation", "type" => "feature_request"}] =
             response["data"]

    assert item_id == "manual:#{item.id}"
    assert response["pagination"]["total_count"] == 1

    show_conn =
      build_conn()
      |> authorize(token)
      |> get("/api/v1/forage/#{URI.encode_www_form(item_id)}")

    assert json_response(show_conn, 200)["data"]["body"] ==
             "Expose forage items in the mobile application."
  end

  test "validates pagination parameters from the OpenAPI contract", %{conn: conn} do
    {token, _user} = mobile_access_token!("pagination@example.com", "mobile", @resource)

    response =
      conn
      |> authorize(token)
      |> get(~p"/api/v1/forage?page_size=101")
      |> json_response(422)

    assert response["errors"] != []
  end

  test "does not expose a missing item", %{conn: conn} do
    {token, _user} = mobile_access_token!("missing@example.com", "mobile", @resource)

    response =
      conn
      |> authorize(token)
      |> get("/api/v1/forage/manual%3Amissing")
      |> json_response(404)

    assert response["error"] == "not_found"
  end

  defp authorize(conn, token),
    do: put_req_header(conn, "authorization", "Bearer #{token.value}")
end
