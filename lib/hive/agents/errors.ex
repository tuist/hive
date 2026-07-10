defmodule Hive.Agents.Errors do
  @moduledoc """
  Normalizes model-provider failures before they reach worker logs or Oban.
  """

  @hard_statuses [401, 402, 412]

  @credit_fragments [
    "credit_limit",
    "credit limit",
    "insufficient credits",
    "payment required",
    "zero balance"
  ]

  @credential_fragments [
    "invalid api key",
    "invalid_api_key",
    "missing or invalid inference token",
    "unauthorized"
  ]

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

  def hard_failure?(reason), do: not is_nil(hard_failure_reason(reason))

  def hard_failure_reason(reason) do
    text = reason_text(reason)

    cond do
      contains_any?(text, @credit_fragments) ->
        :llm_credit_limit

      contains_any?(text, @provider_unavailable_fragments) ->
        :llm_provider_unavailable

      contains_any?(text, @credential_fragments) ->
        :llm_invalid_credentials

      status_code(reason) in @hard_statuses ->
        :llm_provider_rejected_request

      true ->
        nil
    end
  end

  def oban_error(reason, fallback \\ :agent_failed) do
    case hard_failure_reason(reason) do
      nil -> {:error, sanitize_reason(reason, fallback)}
      hard_reason -> {:cancel, hard_reason}
    end
  end

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

  defp reason_text(reason) do
    reason
    |> inspect(limit: 100, printable_limit: 2_000)
    |> String.downcase()
  end

  defp contains_any?(text, fragments),
    do: Enum.any?(fragments, &String.contains?(text, &1))

  defp status_code({:error, reason}), do: status_code(reason)
  defp status_code(status) when is_integer(status) and status in 100..599, do: status
  defp status_code(%{status: status}) when is_integer(status), do: status
  defp status_code(%{"status" => status}) when is_integer(status), do: status
  defp status_code(%{body: body}), do: status_code(body)
  defp status_code(%{"body" => body}), do: status_code(body)
  defp status_code(%{reason: reason}), do: status_code(reason)
  defp status_code(%{"reason" => reason}), do: status_code(reason)
  defp status_code(%{"error" => error}), do: status_code(error)

  defp status_code(values) when is_list(values), do: Enum.find_value(values, &status_code/1)

  defp status_code(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.find_value(&status_code/1)
  end

  defp status_code(map) when is_map(map) do
    map
    |> Map.values()
    |> Enum.find_value(&status_code/1)
  end

  defp status_code(_reason), do: nil

  defp truncate_message(message) do
    message
    |> String.trim()
    |> String.slice(0, 300)
  end
end
