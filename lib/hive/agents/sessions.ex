defmodule Hive.Agents.Sessions do
  @moduledoc """
  Single call site for every Condukt-driven agentic run in Hive.

  Wraps `Condukt.run/3`, `Condukt.stream/3`, and
  `Condukt.Operation.run/4`, merging in the LLM connection options
  resolved by `Hive.Agents` so individual agents stay free of LLM plumbing.
  Callers can select a dedicated runtime profile with `:inference_role`;
  caller-supplied model options win on key collision.

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
  @operation_max_turns 3

  @doc """
  Runs an agent module with the given prompt. Caller-supplied opts are
  merged on top of the resolved LLM client options.
  """
  def run(agent_module, prompt, opts \\ [])
      when is_atom(agent_module) and is_binary(prompt) and is_list(opts) do
    {inference_role, opts} = Keyword.pop(opts, :inference_role, :inference)

    with {:ok, llm_opts} <- client_opts(inference_role) do
      Audit.with_context(agent_actor_context(agent_module, llm_opts), fn ->
        Condukt.run(agent_module, prompt, run_opts(llm_opts, opts))
      end)
    end
  end

  @doc """
  Runs an agent and returns the portable conversation that was created during
  the run. Thinking blocks are deliberately omitted from the durable session;
  user prompts, assistant text, tool calls, and tool results are preserved.
  """
  def run_with_session(agent_module, prompt, opts \\ [])
      when is_atom(agent_module) and is_binary(prompt) and is_list(opts) do
    {inference_role, opts} = Keyword.pop(opts, :inference_role, :inference)

    with {:ok, llm_opts} <- client_opts(inference_role) do
      run_opts = run_opts(llm_opts, opts)

      Audit.with_context(agent_actor_context(agent_module, llm_opts), fn ->
        run_transient_session(agent_module, prompt, run_opts, llm_opts)
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
    {inference_role, opts} = Keyword.pop(opts, :inference_role, :inference)

    with {:ok, llm_opts} <- client_opts(inference_role) do
      run_opts = run_opts(llm_opts, opts)

      Audit.with_context(agent_actor_context(agent_module, llm_opts), fn ->
        consume_stream(agent_module, prompt, run_opts, consume)
      end)
    end
  end

  @doc """
  Runs a typed operation on an agent module with structured args.
  """
  def run_operation(agent_module, operation_name, args, opts \\ [])
      when is_atom(agent_module) and is_atom(operation_name) and is_map(args) and is_list(opts) do
    {inference_role, opts} = Keyword.pop(opts, :inference_role, :inference)
    opts = Keyword.put_new(opts, :max_turns, @operation_max_turns)

    with {:ok, llm_opts} <- client_opts(inference_role) do
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

  defp client_opts(:inference), do: Hive.Agents.client_opts()
  defp client_opts(:coding), do: Hive.Agents.coding_client_opts()

  defp consume_stream(agent_module, prompt, run_opts, consume) do
    Condukt.Session.with_transient(agent_module, run_opts, fn agent ->
      agent
      |> Condukt.stream(prompt, run_opts)
      |> consume.()
    end)
  end

  defp run_transient_session(agent_module, prompt, run_opts, llm_opts) do
    Condukt.Session.with_transient(agent_module, run_opts, fn agent ->
      result = Condukt.run(agent, prompt, run_opts)
      session = portable_session(agent, agent_module, llm_opts)

      case result do
        {:ok, response} -> {:ok, %{result: response, session: session}}
        {:error, reason} -> {:error, reason, session}
      end
    end)
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

  defp portable_session(agent, agent_module, llm_opts) do
    %{
      "id" => Condukt.Session.id(agent),
      "agent" => inspect(agent_module),
      "model" => Keyword.get(llm_opts, :model),
      "messages" => agent |> Condukt.history() |> Enum.map(&portable_message/1)
    }
  end

  defp portable_message(%Condukt.Message{} = message) do
    %{
      "role" => Atom.to_string(message.role),
      "content" => portable_content(message.content),
      "tool_call_id" => message.tool_call_id,
      "timestamp" => message.timestamp && DateTime.to_iso8601(message.timestamp)
    }
  end

  defp portable_content(content) when is_binary(content), do: content

  defp portable_content(blocks) when is_list(blocks) do
    blocks
    |> Enum.flat_map(fn
      {:text, text} ->
        [%{"type" => "text", "text" => text}]

      {:tool_call, id, name, args} ->
        [%{"type" => "tool_call", "id" => id, "name" => name, "arguments" => json_value(args)}]

      {:thinking, _thinking} ->
        []

      block ->
        [%{"type" => "unknown", "value" => inspect(block, limit: 50, printable_limit: 10_000)}]
    end)
  end

  defp portable_content(content), do: json_value(content)

  defp json_value(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), json_value(nested)} end)
  end

  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)
  defp json_value(nil), do: nil
  defp json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp json_value(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp json_value(value), do: inspect(value, limit: 50, printable_limit: 10_000)
end
