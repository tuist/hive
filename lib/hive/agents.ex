defmodule Hive.Agents do
  @moduledoc """
  Entry point for Hive's Condukt-backed agentic workflows.

  Resolves Hive's own inference profile from the runtime model gateway,
  falling back to the global LLM configuration in `:hive, :llm` (populated
  by `config/runtime.exs` from `HIVE_LLM_API_KEY`, `HIVE_LLM_MODEL`, and
  `HIVE_LLM_BASE_URL`). Every AI-backed feature shares the same
  provider/model: when unconfigured, callers receive
  `{:error, :llm_not_configured}` and the feature stays dormant.

  Individual agents live under `lib/hive/<domain>/agents/` and call
  `Hive.Agents.Sessions.run/3`, which transparently merges the LLM
  client options below into every Condukt call.
  """

  alias Hive.Inference

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
  def enabled?, do: Inference.get_hive_profile(:inference) != nil or config() != nil

  @doc """
  Returns `{:ok, keyword}` with the options to pass to `Condukt.run/3`
  (`model`, `api_key`, `base_url`), or `{:error, :llm_not_configured}`
  when the LLM is unconfigured. `Hive.Agents.Sessions` calls this for
  every run, so individual agents don't have to.
  """
  def client_opts(conf \\ Application.get_env(:hive, :llm, [])) do
    case hive_profile_client_opts(:inference) do
      {:ok, opts} -> {:ok, opts}
      {:error, :hive_profile_not_configured} -> configured_client_opts(conf)
      {:error, :llm_not_configured} -> {:error, :llm_not_configured}
    end
  end

  @doc """
  Returns OpenAI-compatible client options for Hive's embedding profile.
  """
  def embedding_client_opts do
    case hive_profile_client_opts(:embedding) do
      {:error, :hive_profile_not_configured} -> {:error, :llm_not_configured}
      result -> result
    end
  end

  defp configured_client_opts(conf) do
    case config(conf) do
      nil ->
        {:error, :llm_not_configured}

      llm ->
        opts =
          [model: llm.model, api_key: llm.api_key]
          |> maybe_put(:base_url, llm.base_url)

        {:ok, opts}
    end
  end

  defp hive_profile_client_opts(role) do
    case Inference.get_hive_profile(role) do
      nil ->
        {:error, :hive_profile_not_configured}

      profile ->
        with {:ok, {_token, token_value}} <- Inference.ensure_hive_token(profile, role) do
          {:ok,
           [
             model: "openai:#{profile.name}",
             api_key: token_value,
             base_url: HiveWeb.Endpoint.url() <> "/inference/v1"
           ]}
        else
          {:error, _reason} -> {:error, :llm_not_configured}
        end
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
