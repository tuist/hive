defmodule HiveWeb.Plugs.OAuthBearerAuthentication do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  alias Boruta.Oauth.Token
  alias Hive.Accounts
  alias Hive.Audit
  alias HiveWeb.RequestOrigin

  def call(conn, opts) do
    scope = Keyword.fetch!(opts, :scope)
    resource_path = Keyword.fetch!(opts, :resource_path)

    with {:ok, token_value} <- bearer_token(conn),
         %Token{sub: user_id, scope: token_scope} = token <-
           Boruta.Ecto.AccessTokens.get_by(value: token_value),
         :ok <- Token.ensure_valid(token),
         true <- scope_allowed?(token_scope, scope),
         true <- resource_allowed?(conn, token, resource_path),
         user when not is_nil(user) <- Accounts.get_user(user_id) do
      Audit.put_context(%{actor: user, interface: Keyword.fetch!(opts, :interface)})
      assign(conn, :current_user, user)
    else
      _error -> unauthorized(conn, opts)
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _header -> :error
    end
  end

  defp scope_allowed?(token_scope, required_scope) when is_binary(token_scope),
    do: required_scope in String.split(token_scope, " ", trim: true)

  defp scope_allowed?(_token_scope, _required_scope), do: false

  defp resource_allowed?(conn, %Token{resource: resource}, resource_path),
    do: resource == "#{RequestOrigin.from_conn(conn)}#{resource_path}"

  defp unauthorized(conn, opts) do
    metadata = "#{RequestOrigin.from_conn(conn)}#{Keyword.fetch!(opts, :metadata_path)}"

    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(Bearer realm="#{Keyword.fetch!(opts, :realm)}", resource_metadata="#{metadata}")
    )
    |> put_status(:unauthorized)
    |> json(%{error: "invalid_token", error_description: "Missing or invalid access token."})
    |> halt()
  end
end
