defmodule Hive.MCP.Components.Tools.RequestSpecReview do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "request_spec_review",
    title: "Request Spec Review",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["id", "expected_revision"],
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "Spec UUID, public number, or /specs/:number URL."
        },
        "expected_revision" => %{
          "type" => "integer",
          "description" => "The latest spec revision observed by the caller."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "ok" => %{"type" => "boolean"},
          "spec" => Hive.MCP.Components.Tools.Specs.spec_schema()
        },
        ["ok", "spec"],
        %{
          "current_revision" => %{"type" => "integer"},
          "spec" => Hive.MCP.Components.Tools.Specs.spec_schema()
        }
      )

  alias Hive.MCP.Components.Tools.Specs, as: SpecTool
  alias Hive.Specs

  @impl EMCP.Tool
  def description do
    "Ask for another review of a Hive spec by posting the latest revision to the configured Slack notification channel. Organization member only."
  end

  @impl EMCP.Tool
  def call(conn, %{"id" => id, "expected_revision" => expected_revision}) do
    spec = Specs.get_spec_by_reference!(id)

    cond do
      not Specs.can_view?(spec, conn.assigns.current_user) ->
        json_response(%{error: "not_found"})

      spec.lock_version != expected_revision ->
        json_response(%{
          error: "stale_revision",
          current_revision: spec.lock_version,
          spec: SpecTool.spec_json(spec)
        })

      true ->
        request_review(conn, spec)
    end
  end

  defp request_review(conn, spec) do
    case Specs.request_review(spec, conn.assigns.current_user) do
      {:ok, spec} ->
        json_response(%{ok: true, spec: SpecTool.spec_json(Specs.get_spec!(spec.id))})

      {:error, :slack_notifications_not_configured} ->
        json_response(%{error: "slack_notifications_not_configured"})

      {:error, :unauthorized} ->
        json_response(%{error: "unauthorized"})

      {:error, _reason} ->
        json_response(%{error: "failed"})
    end
  end
end
