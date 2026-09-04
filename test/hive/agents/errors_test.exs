defmodule Hive.Agents.ErrorsTest do
  use ExUnit.Case, async: true

  alias Hive.Agents.Errors

  describe "hard_failure_reason/1" do
    test "classifies credit-limit failures as hard failures" do
      reason =
        ReqLLM.Error.API.Request.exception(
          reason: "Provider response error (402): credit_limit",
          status: 402,
          response_body: "payment required",
          request_body: "full prompt body"
        )

      assert Errors.hard_failure?(reason)
      assert Errors.hard_failure_reason(reason) == :llm_credit_limit
      assert Errors.oban_error(reason) == {:cancel, :llm_credit_limit}
    end

    test "classifies rejected requests (400) as hard failures" do
      reason =
        ReqLLM.Error.API.Request.exception(
          reason: "Provider response error (400): Openai API error",
          status: 400,
          response_body: "bad request",
          request_body: "full prompt body"
        )

      assert Errors.hard_failure?(reason)
      assert Errors.hard_failure_reason(reason) == :llm_provider_rejected_request
      assert Errors.oban_error(reason) == {:cancel, :llm_provider_rejected_request}
    end

    test "classifies invalid request parameters as hard failures" do
      reason =
        ReqLLM.Error.Invalid.Parameter.exception(
          parameter: "model: openai:hive-inference does not support embedding operations"
        )

      assert Errors.hard_failure?(reason)
      assert Errors.hard_failure_reason(reason) == :llm_provider_rejected_request
      assert Errors.oban_error(reason) == {:cancel, :llm_provider_rejected_request}
    end

    test "keeps rate limits retryable" do
      reason =
        ReqLLM.Error.API.Request.exception(
          reason: "Provider response error (429): Too many requests due to rate limit.",
          status: 429,
          response_body: "too many requests",
          request_body: "full prompt body"
        )

      refute Errors.hard_failure?(reason)
      assert {:error, {:llm_request_failed, 429, _message}} = Errors.oban_error(reason)
    end

    test "keeps request timeouts retryable" do
      reason =
        ReqLLM.Error.API.Request.exception(
          reason: "Provider response error (408): Request timed out.",
          status: 408,
          response_body: "request timeout",
          request_body: "full prompt body"
        )

      refute Errors.hard_failure?(reason)
      assert {:error, {:llm_request_failed, 408, _message}} = Errors.oban_error(reason)
    end
  end

  describe "sanitize_reason/2" do
    test "keeps the message of exceptions it does not know" do
      reason = ReqLLM.Error.Invalid.Parameter.exception(parameter: "text: cannot be empty")

      assert {:error, ReqLLM.Error.Invalid.Parameter, message} = Errors.sanitize_reason(reason)
      assert message =~ "text: cannot be empty"
    end

    test "is idempotent on already-sanitized llm request and response failures" do
      request = {:llm_request_failed, 502, "Provider response error (502): bad gateway"}
      response = {:llm_response_failed, 500, "Provider response error (500): parse error"}

      assert Errors.sanitize_reason(request) == request
      assert Errors.sanitize_reason(response) == response
    end
  end

  describe "reconsiderable_reasons/0 and reconsideration_cooldown/1" do
    test "credit, availability, and transient-exhausted reasons are reconsidered" do
      assert :llm_credit_limit in Errors.reconsiderable_reasons()
      assert :llm_provider_unavailable in Errors.reconsiderable_reasons()
      assert :llm_transient_exhausted in Errors.reconsiderable_reasons()
      refute :llm_invalid_credentials in Errors.reconsiderable_reasons()
      refute :llm_provider_rejected_request in Errors.reconsiderable_reasons()
    end

    test "record-stored names round-trip through the string form" do
      assert "llm_credit_limit" in Errors.reconsiderable_reason_names()
      assert "llm_provider_unavailable" in Errors.reconsiderable_reason_names()
      assert "llm_transient_exhausted" in Errors.reconsiderable_reason_names()
    end

    test "account outages get a short cooldown, retry-exhausted a long one" do
      assert Errors.reconsideration_cooldown(:llm_credit_limit) == 3_600
      assert Errors.reconsideration_cooldown(:llm_provider_unavailable) == 3_600
      assert Errors.reconsideration_cooldown(:llm_transient_exhausted) == 86_400
      assert Errors.reconsideration_cooldown("llm_provider_unavailable") == 3_600
      assert Errors.reconsideration_cooldown(:llm_invalid_credentials) == nil
    end

    test "shortest cooldown is the sweeper SQL cutoff" do
      assert Errors.shortest_reconsideration_cooldown() == 3_600
    end
  end

  describe "provider_unavailable?/1" do
    test "5xx responses from the gateway are unavailability, not permanent" do
      reason =
        ReqLLM.Error.API.Request.exception(
          reason: "Provider response error (502): The upstream provider request failed.",
          status: 502,
          response_body: "bad gateway",
          request_body: "full prompt body"
        )

      assert Errors.provider_unavailable?(reason)
      assert Errors.unavailability_signal(reason) == :status_5xx
      refute Errors.hard_failure?(reason)
    end

    test "408 request timeouts and 429 rate limits count as unavailable" do
      timeout =
        ReqLLM.Error.API.Request.exception(
          reason: "Provider response error (408): Request timed out.",
          status: 408,
          response_body: "request timeout",
          request_body: "full prompt body"
        )

      rate =
        ReqLLM.Error.API.Request.exception(
          reason: "Provider response error (429): rate limit hit",
          status: 429,
          response_body: "too many requests",
          request_body: "full prompt body"
        )

      assert Errors.provider_unavailable?(timeout)
      assert Errors.provider_unavailable?(rate)
    end

    test "transport failures with no status count as unavailable" do
      tls =
        ReqLLM.Error.API.Request.exception(
          reason: "TLS client: In state wait_cert_cr generated CLIENT ALERT",
          status: nil,
          response_body: "",
          request_body: ""
        )

      assert Errors.provider_unavailable?(tls)
      assert Errors.unavailability_signal(tls) == :transport
    end

    test "malformed local requests are not treated as provider unavailability" do
      reason =
        ReqLLM.Error.Invalid.Parameter.exception(
          parameter: "model: openai:hive-inference does not support embedding operations"
        )

      refute Errors.provider_unavailable?(reason)
      assert Errors.hard_failure_reason(reason) == :llm_provider_rejected_request
    end
  end

  describe "terminal_attempt?/1" do
    test "true when the job is on its last Oban attempt" do
      assert Errors.terminal_attempt?(%{attempt: 3, max_attempts: 3})
      assert Errors.terminal_attempt?(%{attempt: 4, max_attempts: 3})
    end

    test "false while attempts remain" do
      refute Errors.terminal_attempt?(%{attempt: 1, max_attempts: 3})
      refute Errors.terminal_attempt?(%{attempt: 2, max_attempts: 3})
    end

    test "false when the shape does not carry attempts" do
      refute Errors.terminal_attempt?(%{})
      refute Errors.terminal_attempt?(nil)
    end
  end
end
