defmodule HiveWeb.OpenGraphController do
  @moduledoc false

  use HiveWeb, :controller

  alias HiveWeb.OpenGraph

  def show(conn, %{"page_id" => page_id, "hash" => hash}) do
    with {:ok, data} <- OpenGraph.page(page_id),
         true <- OpenGraph.valid_hash?(data, hash) do
      OpenGraph.serve(conn, data)
    else
      _other ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(:not_found, "Not found")
    end
  end
end
