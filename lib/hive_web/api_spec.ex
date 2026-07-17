defmodule HiveWeb.ApiSpec do
  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.Components
  alias OpenApiSpex.Info
  alias OpenApiSpex.OAuthFlow
  alias OpenApiSpex.OAuthFlows
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Paths
  alias OpenApiSpex.SecurityScheme
  alias OpenApiSpex.Server

  @impl OpenApiSpex.OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "Hive Mobile API",
        description:
          "Read-only access to the Hive resources shown in the native mobile applications.",
        version: "1.0.0"
      },
      servers: [%Server{url: "/"}],
      paths: Paths.from_router(HiveWeb.Router),
      components: %Components{
        securitySchemes: %{
          "oauth2" => %SecurityScheme{
            type: "oauth2",
            description:
              "Dynamic public-client authorization with an authorization code and Proof Key for Code Exchange.",
            flows: %OAuthFlows{
              authorizationCode: %OAuthFlow{
                authorizationUrl: "/oauth2/authorize",
                tokenUrl: "/oauth2/token",
                refreshUrl: "/oauth2/token",
                scopes: %{"mobile" => "Read resources visible in the Hive mobile application."}
              }
            }
          }
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
