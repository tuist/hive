defmodule HiveWeb.Plugs.MobileAPIAuthentication do
  @moduledoc false

  alias Hive.OAuth.Scopes
  alias HiveWeb.Plugs.OAuthBearerAuthentication

  @default_scopes ["mobile" | Scopes.mobile_scopes()]

  def init(opts) do
    scope =
      case Keyword.get(opts, :scope) do
        nil -> @default_scopes
        binary when is_binary(binary) -> ["mobile", binary] |> Enum.uniq()
        list when is_list(list) -> ["mobile" | list] |> Enum.uniq()
      end

    Keyword.put(opts, :scope, scope)
  end

  def call(conn, opts) do
    OAuthBearerAuthentication.call(conn,
      scope: Keyword.fetch!(opts, :scope),
      resource_path: "/api/v1",
      metadata_path: "/.well-known/oauth-protected-resource/api/v1",
      realm: "hive-mobile",
      interface: "mobile"
    )
  end
end
