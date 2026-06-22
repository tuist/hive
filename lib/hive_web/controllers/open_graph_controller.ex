defmodule HiveWeb.OpenGraphController do
  @moduledoc false

  use HiveWeb, :controller

  alias HiveWeb.OpenGraph

  def show(conn, %{"token" => token}) do
    case OpenGraph.verify_token(conn, token) do
      {:ok, data} -> OpenGraph.serve(conn, data)
      {:error, _reason} -> not_found(conn)
    end
  end

  def show(conn, _params), do: not_found(conn)

  defp not_found(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(:not_found, "Not found")
  end
end
