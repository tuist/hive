defmodule Hive.Agents.StructuredOperationTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Agents
  alias Hive.Agents.Sessions
  alias Hive.Agents.StructuredOperation
  alias Hive.Forage.Agents.GitHubIssueClassifierAgent

  @input %{
    business_context: "Test organization",
    candidate_domains: [%{id: "domain-id", name: "Builds"}],
    issue: %{repository: "test/repository", title: "Improve builds"}
  }

  test "requires structured output in one gateway request and returns validated domain ids" do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = JSON.decode!(body)
      assert request["model"] == "Balanced"

      assert request["tool_choice"] == %{
               "type" => "function",
               "function" => %{"name" => "structured_output"}
             }

      assert [%{"function" => %{"name" => "structured_output"}}] = request["tools"]
      assert request["max_tokens"] == 1_200
      send(self(), :gateway_request)

      Req.Test.json(conn, %{
        id: "test-completion",
        object: "chat.completion",
        created: 0,
        model: "Balanced",
        choices: [
          %{
            index: 0,
            finish_reason: "tool_calls",
            message: %{
              role: "assistant",
              content: nil,
              tool_calls: [
                %{
                  id: "result",
                  type: "function",
                  function: %{
                    name: "structured_output",
                    arguments: JSON.encode!(%{domain_ids: ["domain-id"]})
                  }
                }
              ]
            }
          }
        ],
        usage: %{prompt_tokens: 100, completion_tokens: 10, total_tokens: 110}
      })
    end)

    stub(Agents, :client_opts, fn ->
      {:ok,
       [model: "openai:Balanced", api_key: "test-key", base_url: "https://hive.test/inference/v1"]}
    end)

    assert {:ok, %{domain_ids: ["domain-id"]}} =
             Sessions.run_object_operation(GitHubIssueClassifierAgent, :classify_issue, @input,
               req_http_options: [plug: {Req.Test, __MODULE__}]
             )

    assert_received :gateway_request
    refute_received :gateway_request
  end

  test "rejects invalid input before contacting the provider" do
    reject(ReqLLM, :generate_object, 4)

    assert {:error, {:invalid_input, _}} =
             StructuredOperation.run(GitHubIssueClassifierAgent, :classify_issue, %{},
               model: "openai:Balanced"
             )
  end

  test "validates the returned object without another model call" do
    expect(ReqLLM, :generate_object, fn _, _, _, _ ->
      {:ok,
       struct!(ReqLLM.Response,
         id: "test",
         model: "Balanced",
         context: %ReqLLM.Context{},
         object: %{"domain_ids" => "invalid"}
       )}
    end)

    assert {:error, {:invalid_output, _}} =
             StructuredOperation.run(GitHubIssueClassifierAgent, :classify_issue, @input,
               model: "openai:Balanced"
             )
  end

  test "preserves provider failure status without falling back to an agent loop" do
    error = ReqLLM.Error.API.Request.exception(reason: "Payment required", status: 402)
    expect(ReqLLM, :generate_object, fn _, _, _, _ -> {:error, error} end)
    reject(Condukt.Operation, :run, 4)

    assert {:error, ^error} =
             StructuredOperation.run(GitHubIssueClassifierAgent, :classify_issue, @input,
               model: "openai:Balanced"
             )
  end
end
