defmodule Hive.Slack.Workers.UpdateFlightMessageTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Accounts
  alias Hive.Flights.Flight
  alias Hive.Projects
  alias Hive.Slack.API
  alias Hive.Slack.Installation
  alias Hive.Slack.Workers.UpdateFlightMessage

  test "updates the original Slack message with the latest terminal outcome" do
    suffix = System.unique_integer([:positive])

    {:ok, installation} =
      %Installation{}
      |> Installation.changeset(%{
        team_id: "T#{suffix}",
        team_name: "Workspace #{suffix}",
        bot_token: "xoxb-#{suffix}",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "flight-update-#{suffix}@example.com",
        provider: "test",
        provider_uid: "flight-update-#{suffix}"
      })

    {:ok, project} = Projects.create_project(%{name: "Flight update #{suffix}"})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{owner: "tuist", name: "hive-#{suffix}"})

    flight =
      %Flight{}
      |> Flight.changeset(%{
        forage_item_id: "grafana_alert:#{Ecto.UUID.generate()}",
        status: :succeeded,
        objective: :reproduce,
        objective_outcome: :not_reproduced,
        runner: "microsandbox",
        repository_full_name: "tuist/#{repository.name}",
        repository_id: repository.id,
        requested_by_id: user.id,
        trigger: %{
          "source" => "slack",
          "installation_id" => installation.id,
          "channel_id" => "C-flight",
          "thread_ts" => "1.0",
          "message_ts" => "2.0"
        },
        input: %{"title" => "High latency"},
        result: %{
          "type" => "report",
          "objective_outcome" => "not_reproduced",
          "summary" => "The issue did not occur in the recorded environment."
        }
      })
      |> Repo.insert!()

    installation_id = installation.id

    expect(API, :update_message, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-flight"
      assert params["ts"] == "2.0"
      assert params["text"] =~ "*Reproduce Flight completed*"
      assert params["text"] =~ "Not reproduced"
      assert params["text"] =~ "/flights/#{flight.id}"
      {:ok, %{"ok" => true}}
    end)

    assert :ok = perform_job(UpdateFlightMessage, %{"flight_id" => flight.id})
  end
end
