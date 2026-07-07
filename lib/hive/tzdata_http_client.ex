defmodule Hive.TzdataHTTPClient do
  @moduledoc false

  @behaviour Tzdata.HTTPClient

  @impl Tzdata.HTTPClient
  def get(url, headers, options) do
    request(:get, url, headers, options)
  end

  @impl Tzdata.HTTPClient
  def head(url, headers, options) do
    request(:head, url, headers, options)
  end

  defp request(method, url, headers, options) do
    with :ok <- ensure_started(:ssl),
         :ok <- ensure_started(:inets),
         {:ok, response} <-
           :httpc.request(
             method,
             {String.to_charlist(url), request_headers(headers)},
             http_options(options),
             body_format(method)
           ) do
      normalize_response(method, response)
    end
  end

  defp ensure_started(app) do
    case Application.ensure_all_started(app) do
      {:ok, _started} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp request_headers(headers) do
    Enum.map(headers, fn {key, value} ->
      {to_charlist(key), to_charlist(value)}
    end)
  end

  defp http_options(options) do
    [autoredirect: Keyword.get(options, :follow_redirect, false)]
  end

  defp body_format(:get), do: [body_format: :binary]
  defp body_format(:head), do: []

  defp normalize_response(:get, {{_version, status, _reason}, headers, body}) do
    {:ok, {status, response_headers(headers), IO.iodata_to_binary(body)}}
  end

  defp normalize_response(:head, {{_version, status, _reason}, headers, _body}) do
    {:ok, {status, response_headers(headers)}}
  end

  defp normalize_response(:head, {{_version, status, _reason}, headers}) do
    {:ok, {status, response_headers(headers)}}
  end

  defp normalize_response(_method, response) do
    {:error, {:unexpected_response, response}}
  end

  defp response_headers(headers) do
    Enum.map(headers, fn {key, value} ->
      {to_string(key), to_string(value)}
    end)
  end
end
