defmodule Hive.Slack.Workers.UnfurlLinksTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Slack.API
  alias Hive.Slack.Installation
  alias Hive.Slack.Workers.UnfurlLinks
  alias Hive.Specs

  defp installation! do
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

    installation
  end

  defp user! do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "alice-#{suffix}@example.com",
        provider: "test",
        provider_uid: "alice-#{suffix}@example.com"
      })

    user
  end

  defp spec!(title) do
    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => title,
          "body" => "Spec body.",
          "summary" => "Spec summary."
        },
        user!()
      )

    spec
  end

  defp app_url(path), do: HiveWeb.Endpoint.url() <> path

  test "enqueue/4 inserts a job when at least one URL is provided" do
    installation = installation!()

    assert {:ok, _job} =
             UnfurlLinks.enqueue(installation.id, "C-1", "1.0", [app_url("/specs/1")])

    assert_enqueued(
      worker: UnfurlLinks,
      args: %{
        "installation_id" => installation.id,
        "channel" => "C-1",
        "message_ts" => "1.0",
        "urls" => [app_url("/specs/1")]
      }
    )
  end

  test "enqueue/4 returns :skipped when no URLs are provided" do
    installation = installation!()
    assert :skipped = UnfurlLinks.enqueue(installation.id, "C-1", "1.0", [])
    assert all_enqueued() == []
  end

  test "perform/1 calls chat.unfurl with unfurls for known URLs only" do
    installation = installation!()
    spec = spec!("Slack unfurling")
    installation_id = installation.id

    expect(API, :unfurl, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-1"
      assert params["ts"] == "100.0"

      assert Map.keys(params["unfurls"]) == [app_url("/specs/#{spec.number}")]

      assert get_in(params, ["unfurls", app_url("/specs/#{spec.number}"), "title"]) =~
               "Slack unfurling"

      {:ok, %{"ok" => true}}
    end)

    assert :ok =
             perform_job(UnfurlLinks, %{
               "installation_id" => installation.id,
               "channel" => "C-1",
               "message_ts" => "100.0",
               "urls" => [
                 app_url("/specs/#{spec.number}"),
                 "https://example.org/elsewhere"
               ]
             })
  end

  test "perform/1 skips the API call when no URL resolves" do
    installation = installation!()

    reject(&API.unfurl/2)

    assert :ok =
             perform_job(UnfurlLinks, %{
               "installation_id" => installation.id,
               "channel" => "C-1",
               "message_ts" => "100.0",
               "urls" => ["https://example.org/elsewhere"]
             })
  end

  test "perform/1 returns :ok when the installation has disappeared" do
    reject(&API.unfurl/2)

    assert :ok =
             perform_job(UnfurlLinks, %{
               "installation_id" => Ecto.UUID.generate(),
               "channel" => "C-1",
               "message_ts" => "100.0",
               "urls" => [app_url("/specs/1")]
             })
  end
end
