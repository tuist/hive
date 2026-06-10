defmodule Hive.ConduktSandbox do
  @moduledoc """
  Builds the Condukt sandbox spec used by Hive-managed agents.

  The default stays local for development and tests. Production can switch to
  the Kubernetes backend through runtime config, which makes Condukt's built-in
  filesystem and shell tools execute inside a short-lived pod instead of the
  Hive BEAM host.
  """

  @default_local_cwd "/tmp/hive-condukt"
  @default_kubernetes_cwd "/workspace"
  @default_namespace "default"
  @default_image "debian:bookworm-slim"
  @default_active_deadline_seconds 4 * 60 * 60
  @default_ready_timeout 120_000
  @default_heartbeat_interval 60_000

  def enabled? do
    config() |> Keyword.get(:backend, :local) == :kubernetes
  end

  def sandbox_spec(config \\ config()) when is_list(config) do
    case Keyword.get(config, :backend, :local) do
      :kubernetes -> {Condukt.Sandbox.Kubernetes, kubernetes_opts(config)}
      :local -> {Condukt.Sandbox.Local, local_opts(config)}
    end
  end

  defp config do
    Application.get_env(:hive, :condukt_sandbox, [])
  end

  defp local_opts(config) do
    [cwd: Keyword.get(config, :cwd, @default_local_cwd)]
  end

  defp kubernetes_opts(config) do
    [
      namespace: Keyword.get(config, :namespace, @default_namespace),
      image: Keyword.get(config, :image, @default_image),
      service_account: Keyword.get(config, :service_account),
      cwd: Keyword.get(config, :cwd, @default_kubernetes_cwd),
      active_deadline_seconds:
        Keyword.get(config, :active_deadline_seconds, @default_active_deadline_seconds),
      ready_timeout: Keyword.get(config, :ready_timeout, @default_ready_timeout),
      heartbeat_interval: Keyword.get(config, :heartbeat_interval, @default_heartbeat_interval),
      in_cluster: Keyword.get(config, :in_cluster, true),
      resources: Keyword.get(config, :resources, %{}),
      labels: labels(config),
      annotations: Keyword.get(config, :annotations, %{}),
      network_policy: Keyword.get(config, :network_policy),
      network_policy_image: Keyword.get(config, :network_policy_image)
    ]
    |> reject_empty_values()
  end

  defp labels(config) do
    Map.merge(
      %{
        "app.kubernetes.io/name" => "hive-condukt-sandbox",
        "app.kubernetes.io/managed-by" => "hive"
      },
      Keyword.get(config, :labels, %{})
    )
  end

  defp reject_empty_values(values) do
    Enum.reject(values, fn
      {_key, nil} -> true
      {_key, ""} -> true
      {_key, value} when value == %{} -> true
      {_key, value} when value == [] -> true
      _entry -> false
    end)
  end
end
