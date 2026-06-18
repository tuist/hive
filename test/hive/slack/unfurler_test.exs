defmodule Hive.Slack.UnfurlerTest do
  use Hive.DataCase, async: true

  alias Hive.Slack.Unfurler

  defp app_url(path), do: HiveWeb.Endpoint.url() <> path

  test "skips URLs whose host doesn't match the configured endpoint" do
    assert Unfurler.unfurl("https://example.org/specs/1") == :skip
  end

  test "skips malformed URLs" do
    assert Unfurler.unfurl("not a url") == :skip
    assert Unfurler.unfurl("") == :skip
  end

  test "skips Hive-hosted URLs that no registered module handles" do
    assert Unfurler.unfurl(app_url("/account/slack")) == :skip
  end

  test "delegates to the matching unfurl module for /specs/:number" do
    user =
      Hive.Accounts.upsert_from_auth(%{
        email: "alice@example.com",
        provider: "test",
        provider_uid: "alice@example.com"
      })
      |> elem(1)

    {:ok, spec} =
      Hive.Specs.create_spec(
        %{
          "title" => "Slack unfurling",
          "body" => "Add support for link unfurling so links render nicely.",
          "summary" => "Render Hive links inline."
        },
        user
      )

    assert {:ok, payload} = Unfurler.unfurl(app_url("/specs/#{spec.number}"))
    assert payload["title"] =~ "Slack unfurling"
    assert payload["text"] == "Render Hive links inline."
    assert payload["footer"] =~ "spec"
    assert payload["title_link"] == app_url("/specs/#{spec.number}")
  end
end
