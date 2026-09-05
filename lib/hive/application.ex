defmodule Hive.Application do
  @moduledoc false

  use Application

  @start_og_images_browser_pool :hive
                                |> Application.compile_env(:og_images, [])
                                |> Keyword.get(:start_browser_pool, true)

  @impl true
  def start(_type, _args) do
    Hive.Oban.Telemetry.attach()
    ensure_mcp_session_store_started()

    children =
      [
        HiveWeb.Telemetry,
        Hive.Repo,
        {DNSCluster, query: Application.get_env(:hive, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Hive.PubSub},
        {Cachex, name: :hive},
        Hive.Errors.KeyTouches,
        Hive.Errors.DropAlerter,
        Hive.Errors.IssueCoalescer
      ]
      |> maybe_add_clickhouse()
      |> maybe_add_oban()
      |> add_endpoint()
      |> maybe_add_open_graph_browser_pool()

    result = Supervisor.start_link(children, strategy: :one_for_one, name: Hive.Supervisor)
    install_self_monitor()
    result
  end

  @impl true
  def config_change(changed, _new, removed) do
    HiveWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_add_open_graph_browser_pool(children) do
    if @start_og_images_browser_pool do
      List.insert_at(children, -1, HiveWeb.OpenGraph.browser_pool_child_spec())
    else
      children
    end
  end

  defp maybe_add_clickhouse(children) do
    if Application.get_env(:hive, :clickhouse_enabled, false) do
      children ++
        [
          Hive.ClickHouseRepo,
          Hive.IngestRepo,
          Supervisor.child_spec(Hive.Errors.Event.Buffer, id: Hive.Errors.Event.Buffer)
        ]
    else
      children
    end
  end

  defp add_endpoint(children), do: children ++ [HiveWeb.Endpoint]

  defp maybe_add_oban(children) do
    children ++ [{Oban, Hive.Oban.Config.build(Application.fetch_env!(:hive, Oban))}]
  end

  defp ensure_mcp_session_store_started do
    if :ets.whereis(EMCP.SessionStore.ETS) == :undefined do
      EMCP.SessionStore.ETS.init()
    end

    HiveWeb.Plugs.OAuthRegistrationRateLimit.init_table()
  end

  defp install_self_monitor do
    Task.start(fn -> Hive.Errors.SelfMonitor.install() end)
  end
end
