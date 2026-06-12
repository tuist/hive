defmodule Hive.Agents.Sessions do
  @moduledoc """
  Single call site for every Condukt-driven agentic run in Hive.

  Wraps `Condukt.run/3` and `Condukt.Operation.run/4`, merging in the
  LLM connection options resolved by `Hive.Agents.client_opts/0` so
  individual agents stay free of LLM plumbing. Caller-supplied options
  win on key collision.

  Returns `{:error, :llm_not_configured}` when no LLM is configured,
  keeping the rest of the app working when Hive is deployed without
  agentic features.

  Future audit-trail wiring (persisting sessions and tool calls to the
  database, surfacing them in the UI) lands here so every existing agent
  picks it up without changes.
  """

  @doc """
  Runs an agent module with the given prompt. Caller-supplied opts are
  merged on top of the resolved LLM client options.
  """
  def run(agent_module, prompt, opts \\ [])
      when is_atom(agent_module) and is_binary(prompt) and is_list(opts) do
    with {:ok, llm_opts} <- Hive.Agents.client_opts() do
      Condukt.run(agent_module, prompt, Keyword.merge(llm_opts, opts))
    end
  end

  @doc """
  Runs a typed operation on an agent module with structured args.
  """
  def run_operation(agent_module, operation_name, args, opts \\ [])
      when is_atom(agent_module) and is_atom(operation_name) and is_map(args) and is_list(opts) do
    with {:ok, llm_opts} <- Hive.Agents.client_opts() do
      Condukt.Operation.run(agent_module, operation_name, args, Keyword.merge(llm_opts, opts))
    end
  end
end
