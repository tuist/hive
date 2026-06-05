defmodule HiveWeb.Plugs.OAuthRegistrationRateLimit do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  @table __MODULE__
  @window_seconds 60
  @limit 20

  def init(opts), do: opts

  def init_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      _table -> @table
    end

    :ok
  end

  def call(conn, opts) do
    init_table()

    case increment(conn, opts) do
      count when count <= @limit ->
        conn

      _count ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{
          error: "rate_limited",
          error_description: "Too many OAuth client registration requests."
        })
        |> halt()
    end
  end

  defp increment(conn, opts) do
    key = {client_identifier(conn), current_bucket(opts)}

    :ets.update_counter(@table, key, {2, 1}, {key, 0})
  end

  defp current_bucket(opts) do
    now = Keyword.get(opts, :now, fn -> System.system_time(:second) end)

    now.()
    |> div(@window_seconds)
  end

  defp client_identifier(conn) do
    conn.remote_ip
    |> Tuple.to_list()
    |> Enum.join(".")
  end
end
