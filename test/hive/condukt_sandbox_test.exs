defmodule Hive.ConduktSandboxTest do
  use ExUnit.Case, async: true

  alias Hive.ConduktSandbox

  test "returns a local sandbox spec by default" do
    assert {Condukt.Sandbox.Local, [cwd: "/tmp/hive-condukt"]} =
             ConduktSandbox.sandbox_spec([])
  end

  test "returns a Kubernetes sandbox spec with cluster runtime options" do
    assert {Condukt.Sandbox.Kubernetes, opts} =
             ConduktSandbox.sandbox_spec(
               backend: :kubernetes,
               namespace: "hive-condukt",
               image: "ghcr.io/tuist/hive-condukt-sandbox:sha-123",
               service_account: "hive-condukt-sandbox",
               active_deadline_seconds: 900,
               ready_timeout: 30_000,
               heartbeat_interval: false,
               resources: %{
                 requests: %{cpu: "500m", memory: "1Gi"},
                 limits: %{cpu: "2", memory: "4Gi"}
               },
               network_policy: [rules: [allow: ["api.github.com"]], default: :deny],
               network_policy_image: "ghcr.io/tuist/condukt-egress:1.6.3"
             )

    assert opts[:namespace] == "hive-condukt"
    assert opts[:image] == "ghcr.io/tuist/hive-condukt-sandbox:sha-123"
    assert opts[:service_account] == "hive-condukt-sandbox"
    assert opts[:cwd] == "/workspace"
    assert opts[:active_deadline_seconds] == 900
    assert opts[:ready_timeout] == 30_000
    assert opts[:heartbeat_interval] == false
    assert opts[:in_cluster] == true
    assert opts[:resources][:requests][:memory] == "1Gi"
    assert opts[:network_policy][:rules] == [allow: ["api.github.com"]]
    assert opts[:network_policy_image] == "ghcr.io/tuist/condukt-egress:1.6.3"
  end

  test "drops unset optional Kubernetes values" do
    assert {Condukt.Sandbox.Kubernetes, opts} =
             ConduktSandbox.sandbox_spec(backend: :kubernetes, resources: %{})

    refute Keyword.has_key?(opts, :service_account)
    refute Keyword.has_key?(opts, :resources)
    refute Keyword.has_key?(opts, :network_policy)
  end
end
