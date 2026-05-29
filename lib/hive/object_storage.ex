defmodule Hive.ObjectStorage do
  @moduledoc """
  Runtime object storage configuration.

  Hive supports S3-compatible storage through environment variables.
  The module intentionally exposes a small validated surface so callers
  do not have to know how the runtime configuration is represented.
  """

  @required_s3_keys [:bucket, :region, :access_key_id, :secret_access_key]

  @doc "Returns the configured object storage provider."
  def provider do
    :hive
    |> Application.get_env(:object_storage, [])
    |> Keyword.get(:provider, :none)
  end

  @doc "True when an object storage provider is enabled."
  def enabled?, do: provider() != :none

  @doc """
  Returns a validated S3 configuration.

  Returns `:disabled` when no provider is enabled, `{:ok, config}` when
  all required S3 fields are present, or `{:error, {:missing, keys}}`
  when S3 is enabled but incomplete.
  """
  def s3_config do
    :hive
    |> Application.get_env(:object_storage, [])
    |> s3_config()
  end

  def s3_config(config) do
    case Keyword.get(config, :provider, :none) do
      :none ->
        :disabled

      :s3 ->
        s3 = Keyword.get(config, :s3, [])

        missing =
          @required_s3_keys
          |> Enum.reject(fn key -> present?(Keyword.get(s3, key)) end)

        if missing == [] do
          {:ok, Map.new(s3)}
        else
          {:error, {:missing, missing}}
        end
    end
  end

  @doc "Returns the public, non-secret pieces of the S3 configuration."
  def public_s3_config do
    case s3_config() do
      {:ok, config} ->
        Map.drop(config, [:access_key_id, :secret_access_key])

      other ->
        other
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
