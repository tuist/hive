defmodule Hive.MCP.Components.Tools.ListErrorIssues do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_error_issues",
    title: "List Error Issues",
    schema: %{
      "type" => "object",
      "properties" => %{
        "project_id" => %{
          "type" => "string",
          "description" => "Restrict to issues belonging to this project."
        },
        "status" => %{
          "type" => "string",
          "enum" => Enum.map(Hive.Errors.Issue.statuses(), &Atom.to_string/1),
          "description" => "Filter by issue status."
        },
        "search" => %{
          "type" => "string",
          "description" => "Substring match against issue title or culprit."
        },
        "from" => %{
          "type" => "string",
          "description" => "Inclusive ISO 8601 lower bound on last_seen."
        },
        "to" => %{
          "type" => "string",
          "description" => "Inclusive ISO 8601 upper bound on last_seen."
        },
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "issues" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Schemas.error_issue()
          },
          "pagination" => Hive.MCP.Components.Schemas.pagination()
        },
        ["issues", "pagination"]
      )

  alias Hive.Errors
  alias Hive.Errors.Policy

  @impl EMCP.Tool
  def description,
    do:
      "List error issues captured by the Sentry-compatible ingest endpoint. Restricted to organization members."

  @impl EMCP.Tool
  def call(conn, args) do
    user = conn.assigns[:current_user]

    if Policy.authorize?(:error_issue_read, user, nil) do
      {issues, meta} = Errors.paginate_issues(list_opts(args))

      json_response(%{
        issues: Enum.map(issues, &Errors.serialize_issue/1),
        pagination: meta
      })
    else
      json_response(%{error: "forbidden"})
    end
  end

  defp list_opts(args) do
    [
      page: page(args),
      page_size: page_size(args),
      search: present(args, "search"),
      project_id: present(args, "project_id"),
      status: status(args),
      from: parse_datetime(args, "from"),
      to: parse_datetime(args, "to")
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp status(%{"status" => value}) when is_binary(value) do
    case value do
      "unresolved" -> :unresolved
      "resolved" -> :resolved
      "ignored" -> :ignored
      _ -> nil
    end
  end

  defp status(_), do: nil

  defp page(%{"page" => page}) when is_integer(page) and page > 0, do: page
  defp page(_args), do: 1

  defp page_size(%{"page_size" => size}) when is_integer(size) and size > 0, do: min(size, 100)
  defp page_size(_args), do: 25

  defp present(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _value ->
        nil
    end
  end

  defp parse_datetime(args, key) do
    case present(args, key) do
      nil ->
        nil

      value ->
        case DateTime.from_iso8601(value) do
          {:ok, dt, _offset} -> dt
          _ -> nil
        end
    end
  end
end
