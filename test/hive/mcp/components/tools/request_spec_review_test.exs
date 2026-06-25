defmodule Hive.MCP.Components.Tools.RequestSpecReviewTest do
  use Hive.MCPToolCase
  use Oban.Testing, repo: Hive.Repo

  alias Hive.MCP.Components.Tools.RequestSpecReview
  alias Hive.Repo
  alias Hive.Slack.Installation
  alias Hive.Specs

  defp slack_review_notifications! do
    suffix = System.unique_integer([:positive])

    {:ok, _installation} =
      %Installation{}
      |> Installation.changeset(%{
        team_id: "T#{suffix}",
        team_name: "Workspace #{suffix}",
        bot_token: "xoxb-#{suffix}",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        notification_channel_id: "C#{suffix}",
        notification_events: ["spec.review.requested"]
      })
      |> Repo.insert()
  end

  test "requests review for the current spec revision" do
    user = mcp_user()
    slack_review_notifications!()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    response =
      RequestSpecReview.call(mcp_conn(user), %{
        "id" => "/specs/#{spec.number}",
        "expected_revision" => 1
      })
      |> response_json()

    assert response["ok"] == true
    assert response["spec"]["id"] == spec.id

    assert_enqueued(
      worker: Hive.Slack.Workers.SendNotification,
      args: %{
        "event" => "spec.review.requested",
        "spec_id" => spec.id,
        "requester_id" => user.id
      }
    )
  end

  test "rejects stale review requests" do
    user = mcp_user()
    slack_review_notifications!()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)
    {:ok, _spec} = Specs.update_spec(spec, %{"title" => "Updated"}, user)

    response =
      RequestSpecReview.call(mcp_conn(user), %{
        "id" => spec.id,
        "expected_revision" => 1
      })
      |> response_json()

    assert response["error"] == "stale_revision"
    assert response["current_revision"] == 2
  end
end
