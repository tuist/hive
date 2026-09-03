defmodule HiveWeb.ErrorsAPI.EnvelopeController do
  @moduledoc """
  Sentry-compatible ingest endpoint. Accepts envelopes at
  `POST /api/:project_id/envelope/` and hands the raw body to
  `Hive.Errors.Workers.IngestEnvelope` for parsing and storage.

  This endpoint is public but authenticated by DSN public key. The
  `X-Sentry-Auth` header (or `?sentry_key=` fallback, or a `dsn`
  field on the envelope header) identifies the project key; the
  key's project must match the URL's `:project_id`.
  """

  use HiveWeb, :controller

  require Logger

  alias Hive.Errors
  alias Hive.Errors.Auth
  alias Hive.Errors.Envelope

  @max_body_bytes 20 * 1024 * 1024

  def create(conn, %{"project_id" => project_id}) do
    with {:ok, body, conn} <- read_full_body(conn),
         {:ok, body} <- decode_body(body, encoding(conn)),
         {:ok, public_key} <- resolve_public_key(conn, body),
         {:ok, key} <- Errors.fetch_project_key_by_public_key(public_key),
         :ok <- verify_project(key, project_id),
         {:ok, event_id} <- enqueue(project_id, body) do
      Errors.touch_project_key(key)

      conn
      |> put_status(:ok)
      |> put_resp_content_type("application/json")
      |> json(%{id: event_id})
    else
      {:error, :body_too_large} ->
        send_resp(conn, 413, "")

      {:error, :missing_key} ->
        send_resp(conn, 401, "")

      {:error, :not_found} ->
        send_resp(conn, 401, "")

      {:error, :project_mismatch} ->
        send_resp(conn, 403, "")

      {:error, :not_configured} ->
        send_resp(conn, 503, "")

      {:error, reason} ->
        Logger.warning("errors: ingest failed: #{inspect(reason)}")
        send_resp(conn, 400, "")
    end
  end

  defp read_full_body(conn) do
    do_read(conn, "")
  end

  defp do_read(_conn, acc) when byte_size(acc) > @max_body_bytes,
    do: {:error, :body_too_large}

  defp do_read(conn, acc) do
    case Plug.Conn.read_body(conn, length: 1_000_000) do
      {:ok, chunk, conn} -> {:ok, acc <> chunk, conn}
      {:more, chunk, conn} -> do_read(conn, acc <> chunk)
      {:error, _} = err -> err
    end
  end

  defp encoding(conn) do
    conn
    |> Plug.Conn.get_req_header("content-encoding")
    |> List.first()
    |> case do
      nil -> nil
      value -> value |> String.downcase() |> String.trim()
    end
  end

  defp decode_body(body, nil), do: {:ok, body}
  defp decode_body(body, ""), do: {:ok, body}
  defp decode_body(body, "identity"), do: {:ok, body}

  defp decode_body(body, "gzip") do
    {:ok, :zlib.gunzip(body)}
  rescue
    _ -> {:error, :invalid_encoding}
  end

  defp decode_body(body, "deflate") do
    z = :zlib.open()
    :zlib.inflateInit(z)
    result = :zlib.inflate(z, body)
    :zlib.inflateEnd(z)
    :zlib.close(z)
    {:ok, IO.iodata_to_binary(result)}
  rescue
    _ -> {:error, :invalid_encoding}
  end

  defp decode_body(_body, _other), do: {:error, :unsupported_encoding}

  defp resolve_public_key(conn, body) do
    case Auth.extract(conn) do
      {:ok, key} ->
        {:ok, key}

      {:error, :missing_key} ->
        case envelope_dsn(body) do
          {:ok, dsn} -> Auth.extract_from_dsn(dsn)
          :error -> {:error, :missing_key}
        end
    end
  end

  defp envelope_dsn(body) do
    case Envelope.parse(body) do
      {:ok, %{header: %{"dsn" => dsn}}} when is_binary(dsn) -> {:ok, dsn}
      _ -> :error
    end
  end

  defp verify_project(%{project_id: pid}, project_id) do
    if to_string(pid) == to_string(project_id), do: :ok, else: {:error, :project_mismatch}
  end

  defp enqueue(project_id, body) do
    event_id = extract_event_id(body)

    %{"project_id" => project_id, "body" => body}
    |> Hive.Errors.Workers.IngestEnvelope.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> {:ok, event_id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp extract_event_id(body) do
    case Envelope.parse(body) do
      {:ok, %{header: %{"event_id" => id}}} when is_binary(id) ->
        String.replace(id, "-", "")

      {:ok, %{items: items}} ->
        items
        |> Enum.find_value(fn
          %Envelope.Item{type: "event", payload: payload} ->
            case Jason.decode(payload) do
              {:ok, %{"event_id" => id}} when is_binary(id) -> String.replace(id, "-", "")
              _ -> nil
            end

          _ ->
            nil
        end)
        |> case do
          nil -> random_event_id()
          id -> id
        end

      _ ->
        random_event_id()
    end
  end

  defp random_event_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end
end
