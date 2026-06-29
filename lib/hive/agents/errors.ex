defmodule Hive.Agents.Errors do
  @moduledoc """
  Normalizes model-provider failures before they reach worker logs or Oban.
  """

  @provider_unavailable_fragments [
    "billing",
    "failure to pay",
    "insufficient credits",
    "monthly spending limit",
    "quota",
    "spending limit",
    "suspended"
  ]

  @rate_limited_fragments [
    "rate limit",
    "rate_limit",
    "too many requests"
  ]

  @doc """
  Returns true for provider-side availability failures that are not fixed by
  immediately retrying the same job.
  """
  def provider_unavailable?(%ReqLLM.Error.API.Request{} = error) do
    provider_unavailable_error?(error)
  end

  def provider_unavailable?(%ReqLLM.Error.API.Response{} = error) do
    provider_unavailable_error?(error)
  end

  def provider_unavailable?({:fallback_failed, reason, fallback_reason}) do
    provider_unavailable?(reason) or provider_unavailable?(fallback_reason)
  end

  def provider_unavailable?({tag, reason}) when is_atom(tag) do
    provider_unavailable?(reason)
  end

  def provider_unavailable?(_reason), do: false

  def sanitize_reason(reason, fallback \\ :agent_failed)

  def sanitize_reason(%ReqLLM.Error.API.Request{} = error, _fallback) do
    {:llm_request_failed, error.status, truncate_message(Exception.message(error))}
  end

  def sanitize_reason(%ReqLLM.Error.API.Response{} = error, _fallback) do
    {:llm_response_failed, error.status, truncate_message(Exception.message(error))}
  end

  def sanitize_reason({:fallback_failed, reason, fallback_reason}, fallback) do
    {:fallback_failed, sanitize_reason(reason, fallback),
     sanitize_reason(fallback_reason, fallback)}
  end

  def sanitize_reason({tag, reason}, fallback) when is_atom(tag) do
    {tag, sanitize_reason(reason, fallback)}
  end

  def sanitize_reason(reason, _fallback) when is_atom(reason), do: reason

  def sanitize_reason(reason, _fallback) when is_binary(reason) do
    truncate_message(reason)
  end

  def sanitize_reason(%{__struct__: module}, _fallback) when is_atom(module) do
    {:error, module}
  end

  def sanitize_reason(reason, _fallback) when is_tuple(reason) and tuple_size(reason) > 0 do
    {:error, elem(reason, 0)}
  end

  def sanitize_reason(_reason, fallback), do: fallback

  defp provider_unavailable_error?(error) do
    message = error |> Exception.message() |> String.downcase()

    Enum.any?(@provider_unavailable_fragments, &String.contains?(message, &1)) or
      (Map.get(error, :status) == 429 and
         Enum.any?(@rate_limited_fragments, &String.contains?(message, &1)))
  end

  defp truncate_message(message) do
    message
    |> String.trim()
    |> String.slice(0, 300)
  end
end
