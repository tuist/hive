defmodule Hive.MCP.Components.Tools.GetErrorIssue do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_error_issue",
    title: "Get Error Issue",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{"id" => %{"type" => "string", "description" => "Issue id."}}
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"issue" => Hive.MCP.Components.Schemas.error_issue()},
        ["issue"]
      )

  alias Hive.Errors
  alias Hive.Errors.Policy

  @impl EMCP.Tool
  def description, do: "Fetch a single error issue by id. Restricted to organization members."

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]

    cond do
      not Policy.authorize?(:error_issue_read, user, nil) ->
        json_response(%{error: "forbidden"})

      true ->
        case Errors.fetch_issue(id) do
          {:ok, issue} -> json_response(%{issue: Errors.serialize_issue(issue)})
          {:error, :not_found} -> json_response(%{error: "not_found"})
        end
    end
  end
end
