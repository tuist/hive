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

  test "selects the coding profile without forwarding the internal role option" do
    expect(Agents, :coding_client_opts, fn ->
      {:ok, [model: "openai:hive-coding", api_key: "key"]}
    end)

    expect(Condukt, :run, fn NoopAgent, "fix the repository", opts ->
      assert opts[:model] == "openai:hive-coding"
      refute Keyword.has_key?(opts, :inference_role)
      {:ok, "done"}
    end)

    assert {:ok, "done"} =
             Sessions.run(NoopAgent, "fix the repository", inference_role: :coding)
  end

  test "returns a portable session without model thinking blocks" do
    expect(Agents, :coding_client_opts, fn ->
      {:ok, [model: "openai:hive-coding", api_key: "key"]}
    end)

    expect(Condukt.Session, :with_transient, fn NoopAgent, opts, fun ->
      assert opts[:id] == "flight-id"
      fun.(:agent_pid)
    end)

    expect(Condukt, :run, fn :agent_pid, "fix the repository", _opts ->
      {:ok, %{summary: "done"}}
    end)

    expect(Condukt.Session, :id, fn :agent_pid -> "flight-id" end)

    expect(Condukt, :history, fn :agent_pid ->
      [
        Condukt.Message.user("fix the repository"),
        Condukt.Message.assistant([
          {:thinking, "private reasoning"},
          {:tool_call, "call-1", "read", %{path: "lib/hive.ex"}},
          {:text, "I found the issue."}
        ]),
        Condukt.Message.tool_result("call-1", %{content: "source"})
      ]
    end)

    assert {:ok, %{result: %{summary: "done"}, session: session}} =
             Sessions.run_with_session(NoopAgent, "fix the repository",
               inference_role: :coding,
               id: "flight-id"
             )

    assert session["id"] == "flight-id"
    assert session["model"] == "openai:hive-coding"
    assert [user_message, assistant_message, tool_result] = session["messages"]
    assert user_message["content"] == "fix the repository"
    refute inspect(assistant_message) =~ "private reasoning"

    assert [%{"arguments" => %{"path" => "lib/hive.ex"}}, %{"text" => "I found the issue."}] =
             assistant_message["content"]

    assert tool_result["content"] == %{"content" => "source"}
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

  test "caps structured operations at three turns by default" do
    stub(Agents, :client_opts, fn ->
      {:ok, [model: "anthropic:claude-haiku-4-5", api_key: "key"]}
    end)

    expect(Condukt.Operation, :run, fn NoopAgent, :handle, %{prompt: "work"}, opts ->
      assert opts[:max_turns] == 3
      {:ok, %{reply: "done"}}
    end)

    assert {:ok, %{reply: "done"}} =
             Sessions.run_operation(NoopAgent, :handle, %{prompt: "work"})
  end

  test "allows a structured operation to request a lower turn cap" do
    stub(Agents, :client_opts, fn ->
      {:ok, [model: "anthropic:claude-haiku-4-5", api_key: "key"]}
    end)

    expect(Condukt.Operation, :run, fn NoopAgent, :handle, %{prompt: "work"}, opts ->
      assert opts[:max_turns] == 1
      {:ok, %{reply: "done"}}
    end)

    assert {:ok, %{reply: "done"}} =
             Sessions.run_operation(NoopAgent, :handle, %{prompt: "work"}, max_turns: 1)
  end
end
