defmodule HiveWeb.Plugs.OAuthRegistrationRateLimit do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  @table __MODULE__
  @window_seconds 60
  @limit 20
  @retained_buckets 2

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
    bucket = current_bucket(opts)
    prune_expired_buckets(bucket)

    case increment(conn, bucket) do
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

  defp increment(conn, bucket) do
    key = {client_identifier(conn), bucket}

    :ets.update_counter(@table, key, {2, 1}, {key, 0})
  end

  defp prune_expired_buckets(current_bucket) do
    oldest_bucket = current_bucket - @retained_buckets

    @table
    |> :ets.tab2list()
    |> Enum.each(fn
      {{_client, bucket} = key, _count} when bucket < oldest_bucket -> :ets.delete(@table, key)
      _entry -> :ok
    end)
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
