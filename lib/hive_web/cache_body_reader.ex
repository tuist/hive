defmodule HiveWeb.CacheBodyReader do
  @moduledoc false

  def read_body(conn, opts) do
    read_body(conn, opts, [])
  end

  defp read_body(conn, opts, acc) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        body = IO.iodata_to_binary(Enum.reverse([body | acc]))

        conn =
          if conn.request_path == "/webhooks/github" do
            Plug.Conn.put_private(conn, :hive_raw_body, body)
          else
            conn
          end

        {:ok, body, conn}

      {:more, body, conn} ->
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
