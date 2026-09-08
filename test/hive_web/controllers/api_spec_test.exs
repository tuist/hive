defmodule HiveWeb.ApiSpecTest do
  use HiveWeb.ConnCase, async: true

  test "serves an OpenAPI document for the versioned mobile API", %{conn: conn} do
    response = conn |> get(~p"/api/openapi.json") |> json_response(200)

    assert response["openapi"] =~ "3."
    assert response["info"]["title"] == "Hive Mobile API"

    assert response["paths"]["/api/v1/me"]["get"]["security"] == [
             %{"oauth2" => ["mobile.me.read"]}
           ]

    assert response["paths"]["/api/v1/forage"]["get"]["parameters"] != []

    assert response["paths"]["/api/v1/forage"]["get"]["security"] == [
             %{"oauth2" => ["mobile.forage.read"]}
           ]

    assert response["paths"]["/api/v1/specs"]["get"]["security"] == [
             %{"oauth2" => ["mobile.specs.read"]}
           ]

    assert response["paths"]["/api/v1/drops"]["get"]["security"] == [
             %{"oauth2" => ["mobile.drops.read"]}
           ]

    assert response["paths"]["/api/v1/drops/digests"]["get"]["security"] == [
             %{"oauth2" => ["mobile.drops.read"]}
           ]

    assert get_in(response, [
             "components",
             "securitySchemes",
             "oauth2",
             "flows",
             "authorizationCode",
             "scopes"
           ]) ==
             %{
               "mobile" => "Umbrella scope. Requesting it grants every mobile.* scope below.",
               "mobile.me.read" => "Read the signed-in user's profile.",
               "mobile.forage.read" => "Read forage items.",
               "mobile.specs.read" => "Read specifications.",
               "mobile.drops.read" => "Read drops and digests."
             }
  end
end
