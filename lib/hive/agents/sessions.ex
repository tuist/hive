defmodule Hive.Agents.Sessions do
  @moduledoc """
  Single call site for every Condukt-driven agentic run in Hive.

  Wraps `Condukt.run/3`, `Condukt.stream/3`, and
  `Condukt.Operation.run/4`, merging in the LLM connection options
  resolved by `Hive.Agents.client_opts/0` so
  individual agents stay free of LLM plumbing. Caller-supplied options
  win on key collision.

  Each run also installs an audit actor that identifies the agent (see
  `Hive.Audit.agent_actor/2`) for the duration of the call, so any
  `Hive.Audit.record/3` inside the agent's tools attributes the entry to
  the agent (kind `"agent"`) rather than to a system actor. The actor
  context is scoped to the run and restored when it returns.

  Returns `{:error, :llm_not_configured}` when no LLM is configured,
  keeping the rest of the app working when Hive is deployed without
  agentic features.
  """

  alias Hive.Audit

  # Hive's agents are short, single-purpose runs (revision summaries, issue
  # triage, domain evolution), not long interactive sessions. Cap each run so a
  # slow or unresponsive LLM fails fast and frees its agents-queue worker and
  # HTTP connection instead of lingering for Condukt's 5-minute default and
  # starving the shared LLM connection pool. Callers may override `:timeout`.
  @run_timeout :timer.minutes(2)

  @doc """
  Runs an agent module with the given prompt. Caller-supplied opts are
  merged on top of the resolved LLM client options.
  """
  def run(agent_module, prompt, opts \\ [])
      when is_atom(agent_module) and is_binary(prompt) and is_list(opts) do
    with {:ok, llm_opts} <- Hive.Agents.client_opts() do
      Audit.with_context(agent_actor_context(agent_module, llm_opts), fn ->
        Condukt.run(agent_module, prompt, run_opts(llm_opts, opts))
      end)
    end
  end

  @doc """
  Streams an agent module with the given prompt and consumes the stream
  inside the transient Condukt session.
  """
  def stream(agent_module, prompt, consume) when is_function(consume, 1) do
    stream(agent_module, prompt, [], consume)
  end

  def stream(agent_module, prompt, opts, consume)
      when is_atom(agent_module) and is_binary(prompt) and is_list(opts) and
             is_function(consume, 1) do
    with {:ok, llm_opts} <- Hive.Agents.client_opts() do
      run_opts = run_opts(llm_opts, opts)

      Audit.with_context(agent_actor_context(agent_module, llm_opts), fn ->
        Condukt.Session.with_transient(agent_module, run_opts, fn agent ->
          agent
          |> Condukt.stream(prompt, run_opts)
          |> consume.()
        end)
      end)
    end
  end

  @doc """
  Runs a typed operation on an agent module with structured args.
  """
  def run_operation(agent_module, operation_name, args, opts \\ [])
      when is_atom(agent_module) and is_atom(operation_name) and is_map(args) and is_list(opts) do
    with {:ok, llm_opts} <- Hive.Agents.client_opts() do
      Audit.with_context(agent_actor_context(agent_module, llm_opts), fn ->
        Condukt.Operation.run(agent_module, operation_name, args, run_opts(llm_opts, opts))
      end)
    end
  end

  defp run_opts(llm_opts, opts) do
    llm_opts
    |> Keyword.merge(opts)
    |> Keyword.put_new(:timeout, @run_timeout)
  end

  defp agent_actor_context(agent_module, llm_opts) do
    %{actor: Audit.agent_actor(agent_name(agent_module), model: Keyword.get(llm_opts, :model))}
  end

  defp agent_name(agent_module) do
    agent_module
    |> Module.split()
    |> List.last()
    |> to_string()
  end
end
