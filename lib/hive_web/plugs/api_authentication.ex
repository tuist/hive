defmodule HiveWeb.Plugs.APIAuthentication do
  @moduledoc false

  import Phoenix.Controller
  import Plug.Conn

  alias Boruta.Oauth.Token
  alias Hive.Accounts
  alias Hive.Audit
  alias HiveWeb.RequestOrigin

  @api_path "/api/v1"
  @resource_metadata_path "/.well-known/oauth-protected-resource/api/v1"

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token_value} <- bearer_token(conn),
         %Token{sub: user_id, scope: scope} = token <-
           Boruta.Ecto.AccessTokens.get_by(value: token_value),
         :ok <- Token.ensure_valid(token),
         true <- scope_allowed?(scope),
         true <- resource_allowed?(conn, token),
         user when not is_nil(user) <- Accounts.get_user(user_id) do
      Audit.put_context(%{actor: user, interface: "mobile"})
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
    do: "mobile" in String.split(scope, " ", trim: true)

  defp scope_allowed?(_scope), do: false

  defp resource_allowed?(conn, %Token{resource: resource}) do
    resource == "#{RequestOrigin.from_conn(conn)}#{@api_path}"
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(Bearer realm="hive-mobile", resource_metadata="#{RequestOrigin.from_conn(conn)}#{@resource_metadata_path}")
    )
    |> put_status(:unauthorized)
    |> json(%{error: "invalid_token", error_description: "Missing or invalid access token."})
    |> halt()
  end
end
