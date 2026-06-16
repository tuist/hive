defmodule Hive.Application do
  @moduledoc false

  use Application

  @start_og_images_browser_pool :hive
                                |> Application.compile_env(:og_images, [])
                                |> Keyword.get(:start_browser_pool, true)

  @impl true
  def start(_type, _args) do
    ensure_mcp_session_store_started()

    children =
      [
        HiveWeb.Telemetry,
        Hive.Repo,
        {DNSCluster, query: Application.get_env(:hive, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Hive.PubSub},
        HiveWeb.Endpoint,
        Hive.Forage.GitHubIssueSyncer
      ]
      |> maybe_add_open_graph_browser_pool()
      |> maybe_add_oban()

    opts = [strategy: :one_for_one, name: Hive.Supervisor]
    Supervisor.start_link(children, opts)
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

  defp maybe_add_oban(children) do
    if Hive.Agents.enabled?() do
      children ++ [{Oban, Application.fetch_env!(:hive, Oban)}]
    else
      children
    end
  end

  defp ensure_mcp_session_store_started do
    if :ets.whereis(EMCP.SessionStore.ETS) == :undefined do
      EMCP.SessionStore.ETS.init()
    end

    HiveWeb.Plugs.OAuthRegistrationRateLimit.init_table()
  end
end
