defmodule HiveWeb.Plugs.MCPAuthentication do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  alias Boruta.Oauth.Token
  alias Hive.Accounts
  alias HiveWeb.RequestOrigin

  @resource_metadata_path "/.well-known/oauth-protected-resource/mcp"

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token_value} <- bearer_token(conn),
         %Token{sub: user_id, scope: scope} = token <-
           Boruta.Ecto.AccessTokens.get_by(value: token_value),
         :ok <- Token.ensure_valid(token),
         true <- scope_allowed?(scope),
         user when not is_nil(user) <- Accounts.get_user(user_id) do
      assign(conn, :current_user, user)
    else
      _ -> unauthorized(conn)
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> :error
    end
  end

  defp scope_allowed?(scope) when is_binary(scope),
    do: "mcp" in String.split(scope, " ", trim: true)

  defp scope_allowed?(_scope), do: false

  defp unauthorized(conn) do
    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(Bearer realm="hive-mcp", resource_metadata="#{RequestOrigin.from_conn(conn)}#{@resource_metadata_path}")
    )
    |> put_status(:unauthorized)
    |> json(%{error: "invalid_token", error_description: "Missing or invalid access token."})
    |> halt()
  end
end
