defmodule HiveWeb.Plugs.MobileAPIAuthentication do
  @moduledoc false

  alias HiveWeb.Plugs.OAuthBearerAuthentication

  def init(opts), do: opts

  def call(conn, _opts) do
    OAuthBearerAuthentication.call(conn,
      scope: "mobile",
      resource_path: "/api/v1",
      metadata_path: "/.well-known/oauth-protected-resource/api/v1",
      realm: "hive-mobile",
      interface: "mobile"
    )
  end
end
