defmodule Hive.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HiveWeb.Telemetry,
      Hive.Repo,
      {DNSCluster, query: Application.get_env(:hive, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Hive.PubSub},
      # Start a worker by calling: Hive.Worker.start_link(arg)
      # {Hive.Worker, arg},
      # Start to serve requests, typically the last entry
      HiveWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hive.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HiveWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
