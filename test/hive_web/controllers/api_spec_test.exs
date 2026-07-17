defmodule HiveWeb.ApiSpecTest do
  use HiveWeb.ConnCase, async: true

  test "serves an OpenAPI document for the versioned mobile API", %{conn: conn} do
    response = conn |> get(~p"/api/openapi.json") |> json_response(200)

    assert response["openapi"] =~ "3."
    assert response["info"]["title"] == "Hive Mobile API"
    assert response["paths"]["/api/v1/me"]["get"]["security"] == [%{"oauth2" => ["mobile"]}]
    assert response["paths"]["/api/v1/forage"]["get"]["parameters"] != []
    assert response["paths"]["/api/v1/drops"]["get"]["security"] == [%{"oauth2" => ["mobile"]}]

    assert response["paths"]["/api/v1/drops/digests"]["get"]["security"] == [
             %{"oauth2" => ["mobile"]}
           ]

    assert get_in(response, [
             "components",
             "securitySchemes",
             "oauth2",
             "flows",
             "authorizationCode",
             "scopes"
           ]) ==
             %{"mobile" => "Read resources visible in the Hive mobile application."}
  end
end
