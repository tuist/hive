defmodule Hive.MCP.Components.Tools.UnresolveErrorIssue do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "unresolve_error_issue",
    title: "Unresolve Error Issue",
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
  def description,
    do: "Reopen a previously resolved or ignored error issue. Restricted to organization members."

  @impl EMCP.Tool
  def call(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]

    with true <- Policy.authorize?(:error_issue_resolve, user, nil) or {:error, "forbidden"},
         {:ok, issue} <- Errors.fetch_issue(id),
         {:ok, updated} <- Errors.update_issue_status(issue, :unresolved) do
      updated = %{updated | project: issue.project}
      json_response(%{issue: Errors.serialize_issue(updated)})
    else
      {:error, "forbidden"} -> json_response(%{error: "forbidden"})
      {:error, :not_found} -> json_response(%{error: "not_found"})
      {:error, _} = err -> json_response(%{error: "update_failed", detail: inspect(err)})
    end
  end
end
