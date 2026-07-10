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
  end
end
