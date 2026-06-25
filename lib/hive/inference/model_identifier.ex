defmodule Hive.Inference.ModelIdentifier do
  @moduledoc """
  Helpers for models.dev-style model identifiers.
  """

  @provider_format ~r/^[a-z0-9][a-z0-9._-]*$/

  def parse(value) when is_binary(value) do
    case String.split(value, "/", parts: 2) do
      [provider, model] ->
        provider = String.trim(provider)
        model = String.trim(model)

        if valid_provider?(provider) and valid_model_path?(model) do
          {:ok, %{provider: provider, model: model}}
        else
          :error
        end

      _parts ->
        :error
    end
  end

  def parse(_value), do: :error

  def upstream_model(value) do
    case parse(value) do
      {:ok, %{model: model}} -> model
      :error -> value
    end
  end

  defp valid_provider?(provider), do: Regex.match?(@provider_format, provider)

  defp valid_model_path?(model) do
    model != "" and
      not String.match?(model, ~r/\s/) and
      model
      |> String.split("/")
      |> Enum.all?(&(&1 != ""))
  end
end
