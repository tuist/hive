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
  end

  describe "account_failure?/1" do
    test "credit and availability failures describe the account" do
      assert Errors.account_failure?("Your credit limit has been reached")
      assert Errors.account_failure?("account suspended")
      assert Errors.account_failure?("monthly spending limit exceeded")
    end

    test "credential and request failures describe the record or the config" do
      refute Errors.account_failure?("invalid api key")
      refute Errors.account_failure?(:some_other_reason)
    end

    test "account failure names round-trip through what is stored on a record" do
      assert "llm_credit_limit" in Errors.account_failure_names()
      assert "llm_provider_unavailable" in Errors.account_failure_names()
      refute "llm_invalid_credentials" in Errors.account_failure_names()
    end
  end
end
