defmodule HiveWeb.InferenceControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Inference

  setup do
    on_exit(fn -> Inference.delete_process_config() end)
  end

  test "GET /inference/v1/models lists the token-bound model", %{conn: conn} do
    {_binding, token_value} = relay_token!()

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token_value}")
      |> get(~p"/inference/v1/models")
      |> json_response(200)

    assert %{
             "object" => "list",
             "data" => [%{"id" => "blick-code-review", "object" => "model"}]
           } = response
  end

  test "POST /inference/v1/chat/completions rewrites the model before forwarding", %{conn: conn} do
    parent = self()

    put_relay_config(fn request ->
      send(parent, {:upstream_request, request})

      {:ok,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: %{"id" => "chatcmpl-test", "object" => "chat.completion"}
       )}
    end)

    {_binding, token_value} = relay_token!()

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token_value}")
      |> post(~p"/inference/v1/chat/completions", %{
        "model" => "blick-code-review",
        "messages" => [%{"role" => "user", "content" => "Review this change."}]
      })
      |> json_response(200)

    assert response["id"] == "chatcmpl-test"

    assert_received {:upstream_request, request}
    assert Keyword.fetch!(request, :url) == "https://relay.example/v1/chat/completions"
    assert Keyword.fetch!(request, :json)["model"] == "accounts/fireworks/models/kimi-k2p5"
    assert {"authorization", "Bearer upstream-token"} in Keyword.fetch!(request, :headers)
  end

  test "POST /inference/v1/chat/completions forwards Together.ai models", %{conn: conn} do
    parent = self()

    Inference.put_process_config(
      providers: %{
        "togetherai" => %{
          "base_url" => "https://api.together.ai/v1",
          "api_key" => "together-token"
        }
      },
      request: fn request ->
        send(parent, {:upstream_request, request})

        {:ok,
         Req.Response.new(
           status: 200,
           headers: [{"content-type", "application/json"}],
           body: %{"id" => "chatcmpl-together", "object" => "chat.completion"}
         )}
      end
    )

    {_binding, token_value} =
      relay_token!(
        name: "hive-agent",
        upstream_provider: "togetherai",
        upstream_model: "MiniMaxAI/MiniMax-M3"
      )

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token_value}")
      |> post(~p"/inference/v1/chat/completions", %{
        "model" => "hive-agent",
        "messages" => [%{"role" => "user", "content" => "Summarize this issue."}]
      })
      |> json_response(200)

    assert response["id"] == "chatcmpl-together"

    assert_received {:upstream_request, request}
    assert Keyword.fetch!(request, :url) == "https://api.together.ai/v1/chat/completions"
    assert Keyword.fetch!(request, :json)["model"] == "MiniMaxAI/MiniMax-M3"
    assert {"authorization", "Bearer together-token"} in Keyword.fetch!(request, :headers)
  end

  test "POST /inference/v1/chat/completions persists token usage", %{conn: conn} do
    put_relay_config(fn _request ->
      {:ok,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: %{
           "id" => "chatcmpl-test",
           "usage" => %{
             "prompt_tokens" => 1_000,
             "completion_tokens" => 2_000,
             "total_tokens" => 3_000
           }
         }
       )}
    end)

    {binding, token_value} = relay_token!()

    conn
    |> put_req_header("authorization", "Bearer #{token_value}")
    |> post(~p"/inference/v1/chat/completions", %{
      "model" => "blick-code-review",
      "messages" => [%{"role" => "user", "content" => "Review this change."}]
    })
    |> json_response(200)

    period = {DateTime.add(DateTime.utc_now(), -1, :day), DateTime.utc_now()}

    assert %{
             request_count: 1,
             input_tokens: 1_000,
             output_tokens: 2_000,
             total_tokens: 3_000,
             cost_usd: cost_usd
           } = Inference.usage_summary(binding, period)

    assert Decimal.equal?(cost_usd, Decimal.new("0.005"))
  end

  test "POST /inference/v1/chat/completions excludes failed upstream responses from usage analytics",
       %{conn: conn} do
    put_relay_config(fn _request ->
      {:ok,
       Req.Response.new(
         status: 403,
         headers: [{"content-type", "application/json"}],
         body: %{
           "error" => %{"message" => "Your Fireworks account is suspended."},
           "usage" => %{
             "prompt_tokens" => 1_000,
             "completion_tokens" => 2_000,
             "total_tokens" => 3_000
           }
         }
       )}
    end)

    {binding, token_value} = relay_token!()

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token_value}")
      |> post(~p"/inference/v1/chat/completions", %{
        "model" => "blick-code-review",
        "messages" => [%{"role" => "user", "content" => "Review this change."}]
      })
      |> json_response(403)

    assert response["error"]["message"] =~ "suspended"

    period = {DateTime.add(DateTime.utc_now(), -1, :day), DateTime.utc_now()}

    assert %{
             request_count: 0,
             input_tokens: 0,
             output_tokens: 0,
             total_tokens: 0,
             cost_usd: cost_usd
           } = Inference.usage_summary(binding, period)

    assert Decimal.equal?(cost_usd, Decimal.new("0"))
  end

  test "POST /inference/v1/chat/completions bridges a streaming-only upstream", %{conn: conn} do
    parent = self()

    put_relay_config(fn request ->
      send(parent, {:upstream_request, request})

      case Keyword.fetch(request, :into) do
        :error ->
          {:ok,
           Req.Response.new(
             status: 400,
             headers: [{"content-type", "application/json"}],
             body: %{"error" => %{"code" => "streaming_required"}}
           )}

        {:ok, into} ->
          response =
            Req.Response.new(status: 200, headers: [{"content-type", "text/event-stream"}])

          stream =
            """
            data: {"id":"chatcmpl-stream","object":"chat.completion.chunk","created":1725000000,"model":"upstream-model","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"},"finish_reason":null}]}

            data: {"id":"chatcmpl-stream","object":"chat.completion.chunk","created":1725000000,"model":"upstream-model","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30}}

            data: [DONE]

            """

          {first_chunk, second_chunk} = String.split_at(stream, 80)

          assert {:cont, acc} = into.({:data, first_chunk}, {request, response})
          assert {:cont, _acc} = into.({:data, second_chunk}, acc)

          {:ok, %{response | body: nil}}
      end
    end)

    {binding, token_value} = relay_token!()

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token_value}")
      |> post(~p"/inference/v1/chat/completions", %{
        "model" => "blick-code-review",
        "messages" => [%{"role" => "user", "content" => "Review this change."}]
      })
      |> json_response(200)

    assert %{
             "id" => "chatcmpl-stream",
             "object" => "chat.completion",
             "model" => "upstream-model",
             "choices" => [
               %{
                 "finish_reason" => "stop",
                 "message" => %{"role" => "assistant", "content" => "Hello world"}
               }
             ],
             "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30}
           } = response

    assert_received {:upstream_request, initial_request}
    refute Keyword.has_key?(initial_request, :into)

    assert_received {:upstream_request, streamed_request}
    assert Keyword.fetch!(streamed_request, :json)["stream"]
    assert {"accept", "text/event-stream"} in Keyword.fetch!(streamed_request, :headers)

    period = {DateTime.add(DateTime.utc_now(), -1, :day), DateTime.utc_now()}

    assert %{
             request_count: 1,
             input_tokens: 10,
             output_tokens: 20,
             total_tokens: 30
           } = Inference.usage_summary(binding, period)
  end

  test "POST /inference/v1/embeddings rewrites the model before forwarding", %{conn: conn} do
    parent = self()

    put_relay_config(fn request ->
      send(parent, {:upstream_request, request})

      {:ok,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: %{
           "object" => "list",
           "data" => [%{"object" => "embedding", "embedding" => [0.1, 0.2, 0.3], "index" => 0}],
           "usage" => %{"prompt_tokens" => 4, "total_tokens" => 4}
         }
       )}
    end)

    {_binding, token_value} =
      relay_token!(
        name: "atlas-documents",
        upstream_model: "fireworks-ai/accounts/fireworks/models/qwen3-embedding-8b"
      )

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token_value}")
      |> post(~p"/inference/v1/embeddings", %{
        "model" => "atlas-documents",
        "input" => "hello"
      })
      |> json_response(200)

    assert [%{"embedding" => [0.1, 0.2, 0.3]}] = response["data"]

    assert_received {:upstream_request, request}
    assert Keyword.fetch!(request, :url) == "https://relay.example/v1/embeddings"

    assert Keyword.fetch!(request, :json)["model"] ==
             "accounts/fireworks/models/qwen3-embedding-8b"

    assert Keyword.fetch!(request, :json)["input"] == "hello"
    assert {"authorization", "Bearer upstream-token"} in Keyword.fetch!(request, :headers)
  end

  test "POST /inference/v1/embeddings persists token usage", %{conn: conn} do
    put_relay_config(fn _request ->
      {:ok,
       Req.Response.new(
         status: 200,
         headers: [{"content-type", "application/json"}],
         body: %{
           "object" => "list",
           "data" => [%{"object" => "embedding", "embedding" => [0.1], "index" => 0}],
           "usage" => %{"prompt_tokens" => 4_000, "total_tokens" => 4_000}
         }
       )}
    end)

    {binding, token_value} =
      relay_token!(
        name: "atlas-documents-usage",
        upstream_model: "fireworks-ai/accounts/fireworks/models/qwen3-embedding-8b"
      )

    conn
    |> put_req_header("authorization", "Bearer #{token_value}")
    |> post(~p"/inference/v1/embeddings", %{
      "model" => "atlas-documents-usage",
      "input" => "hello"
    })
    |> json_response(200)

    period = {DateTime.add(DateTime.utc_now(), -1, :day), DateTime.utc_now()}

    assert %{
             request_count: 1,
             input_tokens: 4_000,
             output_tokens: 0,
             total_tokens: 4_000,
             cost_usd: cost_usd
           } = Inference.usage_summary(binding, period)

    assert Decimal.equal?(cost_usd, Decimal.new("0.004"))
  end

  test "POST /inference/v1/chat/completions rejects a model outside the token binding", %{
    conn: conn
  } do
    parent = self()
    put_relay_config(fn request -> send(parent, {:upstream_request, request}) end)
    {_binding, token_value} = relay_token!()

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token_value}")
      |> post(~p"/inference/v1/chat/completions", %{"model" => "other-model", "messages" => []})
      |> json_response(403)

    assert response["error"]["message"] =~ "not allowed"
    refute_received {:upstream_request, _request}
  end

  test "POST /inference/v1/chat/completions streams upstream event data", %{conn: conn} do
    put_relay_config(fn request ->
      headers = Keyword.fetch!(request, :headers)
      into = Keyword.fetch!(request, :into)
      response = Req.Response.new(status: 200, headers: [{"content-type", "text/event-stream"}])

      assert Keyword.fetch!(request, :url) == "https://relay.example/v1/chat/completions"
      assert Keyword.fetch!(request, :json)["model"] == "accounts/fireworks/models/kimi-k2p5"
      assert {"authorization", "Bearer upstream-token"} in headers
      assert {"accept", "text/event-stream"} in headers

      stream_chunk =
        "data: {\"id\":\"chatcmpl-stream\",\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":20,\"total_tokens\":30}}\n\n"

      {first_chunk, second_chunk} = String.split_at(stream_chunk, 24)

      assert {:cont, acc} = into.({:data, first_chunk}, {request, response})
      assert {:cont, _acc} = into.({:data, second_chunk}, acc)

      {:ok, %{response | body: nil}}
    end)

    {binding, token_value} = relay_token!()

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token_value}")
      |> put_req_header("accept", "text/event-stream")
      |> post(~p"/inference/v1/chat/completions", %{
        "model" => "blick-code-review",
        "messages" => [],
        "stream" => true
      })

    assert response(conn, 200) =~ "chatcmpl-stream"

    period = {DateTime.add(DateTime.utc_now(), -1, :day), DateTime.utc_now()}

    assert %{
             request_count: 1,
             input_tokens: 10,
             output_tokens: 20,
             total_tokens: 30
           } = Inference.usage_summary(binding, period)
  end

  test "returns an OpenAI-compatible authorization error", %{conn: conn} do
    response =
      conn
      |> get(~p"/inference/v1/models")
      |> json_response(401)

    assert response["error"]["code"] == "invalid_api_key"
  end

  defp relay_token!(attrs \\ %{}) do
    {:ok, binding} =
      Inference.create_model_binding(
        Map.merge(
          %{
            name: "blick-code-review",
            upstream_provider: "fireworks-ai",
            upstream_model: "fireworks-ai/accounts/fireworks/models/kimi-k2p5"
          },
          Map.new(attrs)
        )
      )

    {:ok, {_token, token_value}} =
      Inference.create_token(binding, %{name: "Repository automation"})

    {binding, token_value}
  end

  defp put_relay_config(request_fun) do
    Inference.put_process_config(
      providers: %{
        "fireworks-ai" => %{
          "base_url" => "https://relay.example/v1",
          "api_key" => "upstream-token",
          "input_cost_per_million" => "1.00",
          "output_cost_per_million" => "2.00"
        }
      },
      request: request_fun
    )
  end
end
