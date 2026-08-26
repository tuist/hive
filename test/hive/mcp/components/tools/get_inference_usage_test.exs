defmodule Hive.MCP.Components.Tools.GetInferenceUsageTest do
  use Hive.MCPToolCase

  alias Hive.Inference
  alias Hive.MCP.Components.Tools.GetInferenceUsage

  test "returns profile usage and cost for the selected date range" do
    admin = mcp_user("inference-usage-admin@example.com", :admin)
    profile = profile!()

    {:ok, {token, _token_value}} =
      Inference.create_token(profile, %{name: "Repository automation"})

    assert {:ok, _usage} =
             Inference.record_usage(
               profile,
               token,
               Req.Response.new(
                 status: 200,
                 body: %{
                   "usage" => %{
                     "prompt_tokens" => 1_000,
                     "completion_tokens" => 2_000,
                     "total_tokens" => 3_000
                   }
                 }
               )
             )

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    response =
      admin
      |> mcp_conn()
      |> GetInferenceUsage.call(%{
        "profile_id" => profile.id,
        "start_at" => now |> DateTime.add(-1, :day) |> DateTime.to_iso8601(),
        "end_at" => now |> DateTime.add(1, :day) |> DateTime.to_iso8601()
      })
      |> response_json()

    assert response["scope"] == "profile"
    assert response["scope_id"] == profile.id

    assert response["usage"] == %{
             "request_count" => 1,
             "input_tokens" => 1_000,
             "output_tokens" => 2_000,
             "total_tokens" => 3_000,
             "cost_usd" => "0.005"
           }

    assert response["period"]["start_at"]
    assert response["period"]["end_at"]
  end

  test "rejects incomplete ranges and non-admin users" do
    admin = mcp_user("inference-range-admin@example.com", :admin)

    invalid_response =
      admin
      |> mcp_conn()
      |> GetInferenceUsage.call(%{"start_at" => "2026-01-01"})
      |> response_json()

    assert invalid_response == %{"error" => "invalid_request"}

    forbidden_response =
      mcp_user()
      |> mcp_conn()
      |> GetInferenceUsage.call(%{})
      |> response_json()

    assert forbidden_response == %{"error" => "forbidden"}
  end

  defp profile! do
    {:ok, profile} =
      Inference.create_profile(%{
        name: profile_name("profile"),
        upstream_provider: "openai",
        upstream_model: "gpt-4o-mini",
        input_cost_per_million: "1.00",
        output_cost_per_million: "2.00"
      })

    profile
  end

  defp profile_name(prefix), do: unique_name(prefix) |> String.replace(" ", "-")
end
