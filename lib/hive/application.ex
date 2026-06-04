defmodule Hive.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HiveWeb.Telemetry,
      Hive.Repo,
      {DNSCluster, query: Application.get_env(:hive, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Hive.PubSub},
      {DynamicSupervisor, name: Hive.OpenGraphSupervisor, strategy: :one_for_one},
      HiveWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Hive.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    HiveWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
