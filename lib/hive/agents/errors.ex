defmodule Hive.Agents.Errors do
  @moduledoc """
  Normalizes model-provider failures before they reach worker logs or Oban.
  """

  # A 4xx client error means the provider rejected the request itself, so an
  # identical retry fails the same way (e.g. an unknown model id yields 400).
  # 408 (Request Timeout) and 429 (Too Many Requests) are the transient
  # exceptions that stay retryable.
  @retryable_client_statuses [408, 429]

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

  # Fragments that indicate transient transport-layer failures rather than a
  # malformed local request. Matched against a status-less `ReqLLM.Error.API.Request`
  # message; a local parameter error is caught earlier by `invalid_request?/1`.
  @transport_fragments [
    "closed",
    "connection refused",
    "econnrefused",
    "handshake",
    "nxdomain",
    "timeout",
    "tls"
  ]

  # Reason atoms sweepers reconsider after a per-reason cooldown. Each row's
  # cooldown is the smallest interval that keeps the load off during a real
  # outage but lets us retry once conditions might have changed. The shortest
  # cooldown is used to filter candidate rows in the sweeper query; the
  # per-reason cooldown is applied in-memory before enqueueing so a
  # 1h-cooldown row is not delayed by the 24h ceiling of another reason.
  @reconsiderable_reasons %{
    llm_credit_limit: 3_600,
    llm_provider_unavailable: 3_600,
    llm_transient_exhausted: 86_400
  }

  @doc """
  Returns true for provider-side availability failures that are not fixed by
  immediately retrying the same job.

  Includes explicit HTTP statuses (5xx, 408, 429), transport-layer failures
  such as timeouts and TLS handshake errors, and message fragments naming a
  known provider unavailability condition. Malformed local requests are not
  considered provider unavailability.
  """
  def provider_unavailable?(reason), do: unavailability_signal(reason) != nil

  def hard_failure?(reason), do: not is_nil(hard_failure_reason(reason))

  @doc """
  Reasons a sweeper reconsiders after a per-reason cooldown, atom form.
  """
  def reconsiderable_reasons, do: Map.keys(@reconsiderable_reasons)

  @doc "The reconsiderable reasons as stored on a record (string form)."
  def reconsiderable_reason_names, do: Enum.map(reconsiderable_reasons(), &to_string/1)

  @doc """
  Seconds a sweeper waits before reconsidering a row tombstoned with `reason`.

  Returns `nil` when the reason is not reconsiderable, meaning the row stays
  tombstoned until its inputs change.
  """
  def reconsideration_cooldown(reason) when is_atom(reason),
    do: Map.get(@reconsiderable_reasons, reason)

  def reconsideration_cooldown(reason) when is_binary(reason) do
    case reason_atom(reason) do
      nil -> nil
      atom -> Map.get(@reconsiderable_reasons, atom)
    end
  end

  def reconsideration_cooldown(_reason), do: nil

  @doc """
  Shortest reconsideration cooldown across every reconsiderable reason.

  Sweepers use this as the SQL cutoff and then apply the per-reason cooldown
  in-memory before enqueueing, so a short cooldown is not blocked behind a
  long one.
  """
  def shortest_reconsideration_cooldown do
    @reconsiderable_reasons |> Map.values() |> Enum.min()
  end

  @doc "True when `reason` will be reconsidered by the sweeper after a cooldown."
  def reconsiderable?(reason) do
    reason
    |> hard_failure_reason()
    |> then(&(&1 in reconsiderable_reasons()))
  end

  @doc """
  Returns true when a job is on (or past) its final Oban attempt.

  Callers use it to move retry-exhausted work into a durable tombstone so the
  sweeper does not re-enqueue the same row indefinitely.
  """
  def terminal_attempt?(%{attempt: attempt, max_attempts: max_attempts})
      when is_integer(attempt) and is_integer(max_attempts) do
    attempt >= max_attempts
  end

  def terminal_attempt?(_job), do: false

  defp reason_atom("llm_credit_limit"), do: :llm_credit_limit
  defp reason_atom("llm_provider_unavailable"), do: :llm_provider_unavailable
  defp reason_atom("llm_transient_exhausted"), do: :llm_transient_exhausted
  defp reason_atom(_reason), do: nil

  def hard_failure_reason(reason) do
    text = reason_text(reason)

    cond do
      contains_any?(text, @credit_fragments) ->
        :llm_credit_limit

      contains_any?(text, @provider_unavailable_fragments) ->
        :llm_provider_unavailable

      contains_any?(text, @credential_fragments) ->
        :llm_invalid_credentials

      client_error_rejected?(status_code(reason)) or invalid_request?(reason) ->
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

  def sanitize_reason({:llm_request_failed, _status, _message} = reason, _fallback), do: reason

  def sanitize_reason({:llm_response_failed, _status, _message} = reason, _fallback), do: reason

  def sanitize_reason({tag, reason}, fallback) when is_atom(tag) do
    {tag, sanitize_reason(reason, fallback)}
  end

  def sanitize_reason(reason, _fallback) when is_atom(reason), do: reason

  def sanitize_reason(reason, _fallback) when is_binary(reason) do
    truncate_message(reason)
  end

  def sanitize_reason(%{__struct__: module} = reason, _fallback) when is_atom(module) do
    if is_exception(reason) do
      {:error, module, truncate_message(Exception.message(reason))}
    else
      {:error, module}
    end
  end

  def sanitize_reason(reason, _fallback) when is_tuple(reason) and tuple_size(reason) > 0 do
    {:error, elem(reason, 0)}
  end

  def sanitize_reason(_reason, fallback), do: fallback

  # A request the client library refused to send is malformed, so every retry
  # builds the same invalid request.
  defp invalid_request?(%ReqLLM.Error.Invalid.Parameter{}), do: true

  defp invalid_request?({:fallback_failed, reason, fallback_reason}) do
    invalid_request?(reason) or invalid_request?(fallback_reason)
  end

  defp invalid_request?({tag, reason}) when is_atom(tag), do: invalid_request?(reason)

  defp invalid_request?(_reason), do: false

  @doc false
  # Returns the specific signal that classifies `reason` as provider
  # unavailability, or `nil` when the reason is not a provider outage.
  #
  # Malformed local requests (`ReqLLM.Error.Invalid.Parameter` and their
  # wrappers) are never reported as provider unavailability so retrying them
  # is not confused with waiting out an outage.
  def unavailability_signal(reason) do
    cond do
      invalid_request?(reason) -> nil
      transport_failure?(reason) -> :transport
      status_5xx?(status_code(reason)) -> :status_5xx
      status_code(reason) == 408 -> :status_408
      status_code(reason) == 429 -> :status_429
      message_matches_unavailability?(reason) -> :message_fragment
      true -> nil
    end
  end

  defp status_5xx?(status) when is_integer(status) and status >= 500 and status <= 599, do: true
  defp status_5xx?(_status), do: false

  defp transport_failure?(reason) do
    status_code(reason) == nil and
      contains_any?(reason_text(reason), @transport_fragments) and
      not contains_any?(reason_text(reason), ["invalid parameter"])
  end

  defp message_matches_unavailability?(reason) do
    text = reason_text(reason)

    contains_any?(text, @provider_unavailable_fragments) or
      contains_any?(text, @rate_limited_fragments)
  end

  defp reason_text(reason) do
    reason
    |> inspect(limit: 100, printable_limit: 2_000)
    |> String.downcase()
  end

  defp contains_any?(text, fragments),
    do: Enum.any?(fragments, &String.contains?(text, &1))

  defp client_error_rejected?(status) when is_integer(status),
    do: status in 400..499 and status not in @retryable_client_statuses

  defp client_error_rejected?(_status), do: false

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
