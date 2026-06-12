defmodule Hive.Agents do
  @moduledoc """
  Entry point for Hive's Condukt-backed agentic workflows.

  Reads the global LLM configuration from `:hive, :llm` (populated by
  `config/runtime.exs` from `HIVE_LLM_API_KEY`, `HIVE_LLM_MODEL`, and
  `HIVE_LLM_BASE_URL`). Every AI-backed feature shares the same
  provider/model: when unconfigured, callers receive
  `{:error, :llm_not_configured}` and the feature stays dormant.

  Individual agents live under `lib/hive/<domain>/agents/` and call
  `Hive.Agents.Sessions.run/3`, which transparently merges the LLM
  client options below into every Condukt call.
  """

  @doc """
  Returns the configured LLM as a map, or `nil` when unconfigured.

  Shape: `%{api_key: binary, model: binary, base_url: binary | nil}`.
  """
  def config(conf \\ Application.get_env(:hive, :llm, [])) do
    case Keyword.get(conf, :api_key) do
      empty when empty in [nil, ""] ->
        nil

      api_key ->
        %{
          api_key: api_key,
          model: Keyword.fetch!(conf, :model),
          base_url: Keyword.get(conf, :base_url)
        }
    end
  end

  @doc """
  Returns `true` when the LLM is configured and agents can run.
  """
  def enabled?, do: config() != nil

  @doc """
  Returns `{:ok, keyword}` with the options to pass to `Condukt.run/3`
  (`model`, `api_key`, `base_url`), or `{:error, :llm_not_configured}`
  when the LLM is unconfigured. `Hive.Agents.Sessions` calls this for
  every run, so individual agents don't have to.
  """
  def client_opts do
    case config() do
      nil ->
        {:error, :llm_not_configured}

      llm ->
        opts =
          [model: llm.model, api_key: llm.api_key]
          |> maybe_put(:base_url, llm.base_url)

        {:ok, opts}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
