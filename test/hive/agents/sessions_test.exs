defmodule Hive.Agents.SessionsTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Audit
  alias Hive.Audit.Activity
  alias Hive.Agents
  alias Hive.Agents.Sessions
  alias Hive.TestSupport.Agents.NoopAgent

  test "records inside the run attribute to the agent" do
    stub(Agents, :client_opts, fn ->
      {:ok, [model: "anthropic:claude-haiku-4-5", api_key: "key"]}
    end)

    stub(Condukt, :run, fn _agent, _prompt, _opts ->
      :ok = Audit.record("spec.created", %{target_type: "spec", target_id: "from-agent"})
      {:ok, "done"}
    end)

    assert {:ok, "done"} = Sessions.run(NoopAgent, "draft a spec")

    activity = Repo.get_by!(Activity, action: "spec.created", target_id: "from-agent")

    assert activity.actor_kind == "agent"
    assert activity.actor_name == "NoopAgent"
    assert activity.metadata["agent_model"] == "anthropic:claude-haiku-4-5"
  end

  test "restores the prior actor context when the run returns" do
    stub(Agents, :client_opts, fn ->
      {:ok, [model: "anthropic:claude-haiku-4-5", api_key: "key"]}
    end)

    stub(Condukt, :run, fn _agent, _prompt, _opts -> {:ok, "done"} end)

    Audit.put_context(%{interface: "dashboard"})
    assert {:ok, "done"} = Sessions.run(NoopAgent, "draft a spec")

    # Context outside the run is untouched.
    refute Map.has_key?(Audit.current_context(), :actor_kind)
  end

  test "streams inside a transient session with the agent actor context" do
    stub(Agents, :client_opts, fn ->
      {:ok, [model: "anthropic:claude-haiku-4-5", api_key: "key"]}
    end)

    stub(Condukt.Session, :with_transient, fn NoopAgent, opts, fun ->
      assert opts[:model] == "anthropic:claude-haiku-4-5"
      fun.(:agent_pid)
    end)

    stub(Condukt, :stream, fn :agent_pid, "draft a spec", opts ->
      assert opts[:model] == "anthropic:claude-haiku-4-5"
      [{:text, "done"}]
    end)

    assert {:ok, "done"} =
             Sessions.stream(NoopAgent, "draft a spec", fn events ->
               :ok =
                 Audit.record("spec.created", %{target_type: "spec", target_id: "from-stream"})

               reply =
                 Enum.map_join(events, fn
                   {:text, chunk} -> chunk
                   _event -> ""
                 end)

               {:ok, reply}
             end)

    activity = Repo.get_by!(Activity, action: "spec.created", target_id: "from-stream")

    assert activity.actor_kind == "agent"
    assert activity.actor_name == "NoopAgent"
    assert activity.metadata["agent_model"] == "anthropic:claude-haiku-4-5"
  end
end
