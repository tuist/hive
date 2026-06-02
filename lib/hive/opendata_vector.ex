defmodule Hive.OpendataVector do
  @moduledoc """
  Runtime opendata-vector database configuration.

  Hive uses the opendata-vector HTTP service when
  `HIVE_OPENDATA_VECTOR_URL` is configured.
  """

  @doc "True when an opendata-vector endpoint is configured."
  def enabled?, do: base_url() != :disabled

  @doc """
  Returns the configured opendata-vector base URL.

  Returns `:disabled` when no endpoint is configured, or `{:ok, url}` when
  `HIVE_OPENDATA_VECTOR_URL` is present.
  """
  def base_url do
    :hive
    |> Application.get_env(:opendata_vector, [])
    |> base_url()
  end

  def base_url(config) do
    config
    |> Keyword.get(:base_url)
    |> case do
      value when is_binary(value) ->
        value = String.trim(value)

        if value == "" do
          :disabled
        else
          {:ok, value}
        end

      _other ->
        :disabled
    end
  end
end
