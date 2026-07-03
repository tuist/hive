defmodule HiveWeb.InferenceController do
  use HiveWeb, :controller

  alias Hive.Audit
  alias Hive.Inference
  alias Hive.Inference.ModelBinding
  alias Hive.Inference.Token

  def models(conn, _params) do
    binding = conn.assigns.inference_model_binding

    json(conn, %{
      object: "list",
      data: [
        %{
          id: binding.name,
          object: "model",
          created: unix_time(binding.inserted_at),
          owned_by: "hive"
        }
      ]
    })
  end

  def chat_completions(conn, params) do
    binding = conn.assigns.inference_model_binding
    token = conn.assigns.inference_token

    with {:ok, requested_model} <- fetch_requested_model(params),
         true <- Inference.model_allowed?(binding, requested_model),
         {:ok, request} <- Inference.relay_request(binding, params) do
      if streamed?(params) do
        stream_upstream(conn, binding, token, request)
      else
        proxy_upstream(conn, binding, token, request)
      end
    else
      {:error, :missing_model} ->
        openai_error(
          conn,
          :bad_request,
          "The request must include a model.",
          "invalid_request_error"
        )

      false ->
        openai_error(
          conn,
          :forbidden,
          "This token is not allowed to use the requested model.",
          "invalid_request_error"
        )

      {:error, :upstream_not_configured} ->
        openai_error(
          conn,
          :bad_gateway,
          "The requested model is not configured with an upstream provider.",
          "server_error"
        )
    end
  end

  def embeddings(
        %Plug.Conn{
          assigns: %{
            inference_model_binding: %ModelBinding{} = binding,
            inference_token: %Token{} = token
          }
        } = conn,
        params
      ) do
    with {:ok, requested_model} <- fetch_requested_model(params),
         true <- Inference.model_allowed?(binding, requested_model),
         {:ok, request} <- Inference.relay_embedding_request(binding, params) do
      proxy_upstream(conn, binding, token, request, :embedding)
    else
      {:error, :missing_model} ->
        openai_error(
          conn,
          :bad_request,
          "The request must include a model.",
          "invalid_request_error"
        )

      false ->
        openai_error(
          conn,
          :forbidden,
          "This token is not allowed to use the requested model.",
          "invalid_request_error"
        )

      {:error, :upstream_not_configured} ->
        openai_error(
          conn,
          :bad_gateway,
          "The requested model is not configured with an upstream provider.",
          "server_error"
        )
    end
  end

  defp proxy_upstream(
         conn,
         %ModelBinding{} = binding,
         %Token{} = token,
         request,
         operation \\ :chat_completion
       ) do
    case Inference.request_fun().(request) do
      {:ok, response} ->
        record_relay(binding, token, response, nil, operation)
        send_upstream_response(conn, response, "application/json")

      {:error, _reason} ->
        openai_error(conn, :bad_gateway, "The upstream provider request failed.", "server_error")
    end
  end

  defp stream_upstream(conn, %ModelBinding{} = binding, %Token{} = token, request) do
    conn_ref = make_ref()
    Process.put(conn_ref, conn)
    Process.put(stream_usage_ref(conn_ref), nil)

    request = Keyword.put(request, :into, stream_into(conn_ref))

    response =
      case Inference.request_fun().(request) do
        {:ok, response} ->
          record_relay(
            binding,
            token,
            response,
            Process.get(stream_usage_ref(conn_ref)),
            :chat_completion
          )

          response

        {:error, _reason} ->
          nil
      end

    conn = Process.get(conn_ref)
    Process.delete(conn_ref)
    Process.delete(stream_usage_ref(conn_ref))

    cond do
      chunked?(conn) ->
        conn

      is_nil(response) ->
        openai_error(conn, :bad_gateway, "The upstream provider request failed.", "server_error")

      true ->
        send_upstream_response(conn, response, "text/event-stream")
    end
  end

  defp stream_into(conn_ref) do
    fn {:data, data}, {request, response} ->
      conn =
        conn_ref
        |> Process.get()
        |> ensure_chunked(response, "text/event-stream")

      case chunk(conn, data) do
        {:ok, conn} ->
          put_stream_usage(conn_ref, data)
          Process.put(conn_ref, conn)
          {:cont, {request, response}}

        {:error, _reason} ->
          {:halt, {request, response}}
      end
    end
  end

  defp put_stream_usage(conn_ref, data) do
    case Inference.usage_from_stream_chunk(data) do
      nil -> :ok
      usage -> Process.put(stream_usage_ref(conn_ref), usage)
    end
  end

  defp ensure_chunked(conn, response, fallback_content_type) do
    if chunked?(conn) do
      conn
    else
      conn
      |> put_resp_content_type(content_type(response_headers(response), fallback_content_type))
      |> send_chunked(response_status(response))
    end
  end

  defp send_upstream_response(conn, response, fallback_content_type) do
    conn =
      conn
      |> put_status(response_status(response))
      |> put_resp_content_type(content_type(response_headers(response), fallback_content_type))

    case response_body(response) do
      body when is_map(body) or is_list(body) -> json(conn, body)
      body when is_binary(body) -> send_resp(conn, conn.status, body)
      nil -> send_resp(conn, conn.status, "")
      body -> send_resp(conn, conn.status, to_string(body))
    end
  end

  defp stream_usage_ref(conn_ref), do: {conn_ref, :inference_usage}

  defp record_relay(
         %ModelBinding{} = binding,
         %Token{} = token,
         response,
         usage_payload,
         operation
       ) do
    Inference.touch_model_binding(binding)

    {:ok, usage} =
      Inference.record_usage(binding, token, response, usage_payload, operation: operation)

    Audit.record(:"inference.relayed", %{
      target_type: "inference_model",
      target_id: binding.id,
      target_label: binding.name,
      metadata: %{
        "operation" => usage.operation,
        "upstream_provider" => binding.upstream_provider,
        "upstream_model" => binding.upstream_model,
        "status" => response_status(response),
        "token_id" => token.id,
        "input_tokens" => usage.input_tokens,
        "output_tokens" => usage.output_tokens,
        "total_tokens" => usage.total_tokens,
        "cost_usd" => usage.cost_usd
      }
    })
  end

  defp fetch_requested_model(%{"model" => model}) when is_binary(model) and model != "",
    do: {:ok, model}

  defp fetch_requested_model(%{model: model}) when is_binary(model) and model != "",
    do: {:ok, model}

  defp fetch_requested_model(_params), do: {:error, :missing_model}

  defp streamed?(%{"stream" => true}), do: true
  defp streamed?(%{stream: true}), do: true
  defp streamed?(_params), do: false

  defp response_status(%{status: status}) when is_integer(status), do: status
  defp response_status(_response), do: 200

  defp response_headers(%{headers: headers}) when is_list(headers), do: headers
  defp response_headers(%{headers: headers}) when is_map(headers), do: Map.to_list(headers)
  defp response_headers(_response), do: []

  defp response_body(%{body: body}), do: body
  defp response_body(_response), do: nil

  defp content_type(headers, fallback) do
    Enum.find_value(headers, fallback, fn
      {name, value} when is_binary(name) ->
        if String.downcase(name) == "content-type", do: header_value(value)

      {name, value} when is_atom(name) ->
        if name == :content_type, do: header_value(value)

      _other ->
        nil
    end)
  end

  defp header_value([value | _rest]) when is_binary(value), do: value
  defp header_value(value) when is_binary(value), do: value
  defp header_value(_value), do: nil

  defp chunked?(%Plug.Conn{state: :chunked}), do: true
  defp chunked?(_conn), do: false

  defp unix_time(nil), do: 0
  defp unix_time(%DateTime{} = datetime), do: DateTime.to_unix(datetime)

  defp openai_error(conn, status, message, type) do
    conn
    |> put_status(status)
    |> json(%{
      error: %{
        message: message,
        type: type,
        code: nil
      }
    })
  end
end
