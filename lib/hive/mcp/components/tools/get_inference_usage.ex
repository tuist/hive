defmodule Hive.MCP.Components.Tools.GetInferenceUsage do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_inference_usage",
    title: "Get Inference Usage",
    schema: %{
      "type" => "object",
      "properties" => %{
        "profile_id" => %{"type" => "string", "description" => "Restrict usage to one profile."},
        "token_id" => %{"type" => "string", "description" => "Restrict usage to one token."},
        "start_at" => %{
          "type" => "string",
          "description" =>
            "Inclusive ISO 8601 start date or datetime. Must be paired with end_at."
        },
        "end_at" => %{
          "type" => "string",
          "description" =>
            "Inclusive ISO 8601 end date or datetime. Must be paired with start_at."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "scope" => %{"type" => "string", "enum" => ["organization", "profile", "token"]},
          "scope_id" => %{"type" => ["string", "null"]},
          "period" => Hive.MCP.Components.Schemas.inference_usage_period(),
          "usage" => Hive.MCP.Components.Schemas.inference_usage()
        },
        ["scope", "scope_id", "period", "usage"]
      )

  alias Hive.Inference
  alias Hive.MCP.Components.Tools.Inference, as: InferenceTool
  alias Hive.Ops.Policy

  @impl EMCP.Tool
  def description do
    "Get successful inference request, token, and estimated cost totals for a date range. Only available to admins."
  end

  @impl EMCP.Tool
  def call(conn, args) do
    if Policy.authorize?(:inference_profile_manage, conn.assigns[:current_user], nil) do
      with {:ok, period} <- usage_period(args),
           {:ok, scope, scope_id, subject} <- usage_subject(args) do
        json_response(%{
          scope: scope,
          scope_id: scope_id,
          period: period_json(period),
          usage: InferenceTool.usage_json(Inference.usage_summary(subject, period))
        })
      else
        :not_found -> json_response(%{error: "not_found"})
        :invalid_request -> json_response(%{error: "invalid_request"})
      end
    else
      json_response(%{error: "forbidden"})
    end
  end

  defp usage_subject(args) do
    case {present(args["profile_id"]), present(args["token_id"])} do
      {nil, nil} ->
        {:ok, "organization", nil, nil}

      {profile_id, nil} ->
        case Inference.get_profile(profile_id) do
          nil -> :not_found
          profile -> {:ok, "profile", profile.id, profile}
        end

      {nil, token_id} ->
        case Inference.get_token(token_id) do
          nil -> :not_found
          token -> {:ok, "token", token.id, token}
        end

      {_profile_id, _token_id} ->
        :invalid_request
    end
  end

  defp usage_period(args) do
    case {present(args["start_at"]), present(args["end_at"])} do
      {nil, nil} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        {:ok, {DateTime.add(now, -30, :day), now}}

      {start_at, end_at} when is_binary(start_at) and is_binary(end_at) ->
        with {:ok, start_at} <- parse_datetime(start_at, ~T[00:00:00]),
             {:ok, end_at} <- parse_datetime(end_at, ~T[23:59:59]),
             :lt <- DateTime.compare(start_at, end_at) do
          {:ok, {start_at, end_at}}
        else
          _error -> :invalid_request
        end

      _range ->
        :invalid_request
    end
  end

  defp parse_datetime(value, fallback_time) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        {:ok, DateTime.new!(date, fallback_time, "Etc/UTC")}

      _error ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, DateTime.truncate(datetime, :second)}
          _error -> :invalid_request
        end
    end
  end

  defp period_json({start_at, end_at}) do
    %{start_at: DateTime.to_iso8601(start_at), end_at: DateTime.to_iso8601(end_at)}
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp present(_value), do: nil
end
