defmodule Hive.Slack.Workers.UnfurlLinksTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Slack.API
  alias Hive.Slack.Installation
  alias Hive.Slack.Workers.UnfurlLinks

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

  defp app_url(path), do: HiveWeb.Endpoint.url() <> path

  defp block_texts(%{"blocks" => blocks}) do
    Enum.flat_map(blocks, fn block ->
      [get_in(block, ["text", "text"])] ++
        (block
         |> Map.get("fields", [])
         |> Enum.map(& &1["text"]))
    end)
    |> Enum.reject(&is_nil/1)
  end

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

  test "enqueue/5 keeps Slack composer unfurl target metadata" do
    installation = installation!()

    assert {:ok, _job} =
             UnfurlLinks.enqueue(installation.id, "C-1", "1.0", [app_url("/specs/1")],
               source: "composer",
               unfurl_id: "U-1"
             )

    assert_enqueued(
      worker: UnfurlLinks,
      args: %{
        "installation_id" => installation.id,
        "channel" => "C-1",
        "message_ts" => "1.0",
        "source" => "composer",
        "unfurl_id" => "U-1",
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
    installation_id = installation.id
    known_url = app_url("/ops/slack")
    unknown_url = "https://example.org/elsewhere"

    expect(API, :unfurl, fn %Installation{id: ^installation_id}, params ->
      assert params["channel"] == "C-1"
      assert params["ts"] == "100.0"

      assert Map.keys(params["unfurls"]) == [known_url]

      payload = get_in(params, ["unfurls", known_url])

      assert block_texts(payload) |> Enum.any?(&(&1 == "Slack"))

      {:ok, %{"ok" => true}}
    end)

    assert :ok =
             perform_job(UnfurlLinks, %{
               "installation_id" => installation.id,
               "channel" => "C-1",
               "message_ts" => "100.0",
               "urls" => [known_url, unknown_url]
             })
  end

  test "perform/1 can target Slack composer unfurls" do
    installation = installation!()
    installation_id = installation.id
    url = app_url("/ops/slack")

    expect(API, :unfurl, fn %Installation{id: ^installation_id}, params ->
      assert params["source"] == "composer"
      assert params["unfurl_id"] == "U-1"
      refute Map.has_key?(params, "channel")
      refute Map.has_key?(params, "ts")

      payload = get_in(params, ["unfurls", url])

      assert block_texts(payload) |> Enum.any?(&(&1 == "Slack"))

      {:ok, %{"ok" => true}}
    end)

    assert :ok =
             perform_job(UnfurlLinks, %{
               "installation_id" => installation.id,
               "channel" => "C-1",
               "message_ts" => "100.0",
               "source" => "composer",
               "unfurl_id" => "U-1",
               "urls" => [url]
             })
  end

  test "perform/1 treats missing Slack scopes as handled" do
    installation = installation!()
    installation_id = installation.id
    url = app_url("/ops/slack")

    expect(API, :unfurl, fn %Installation{id: ^installation_id}, _params ->
      {:error, {:slack_api_error, "missing_scope"}}
    end)

    assert :ok =
             perform_job(UnfurlLinks, %{
               "installation_id" => installation.id,
               "channel" => "C-1",
               "message_ts" => "100.0",
               "urls" => [url]
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
