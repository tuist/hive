defmodule HiveWeb.Plugs.APIAuthentication do
  @moduledoc false

  alias HiveWeb.Plugs.OAuthBearerAuthentication

  def init(opts), do: opts

  def call(conn, _opts) do
    OAuthBearerAuthentication.call(conn,
      scope: "api",
      resource_path: "/api",
      metadata_path: "/.well-known/oauth-protected-resource/api",
      realm: "hive-api",
      interface: "api"
    )
  end
end
