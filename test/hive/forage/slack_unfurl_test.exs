defmodule Hive.Forage.SlackUnfurlTest do
  use Hive.DataCase, async: true

  alias Hive.Forage
  alias Hive.Forage.FeatureRequest
  alias Hive.Forage.SlackUnfurl

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

  defp uri(path), do: URI.parse("http://localhost" <> path)

  test "unfurl/1 returns a payload for a public manual feature request" do
    {:ok, item} =
      Forage.create_feature_request(
        %{"title" => "Slack unfurling", "description" => "Render Hive links nicely."},
        user!()
      )

    assert {:ok, payload} = SlackUnfurl.unfurl(uri("/forage/items/manual/#{item.id}"))
    assert payload["title"] == "Slack unfurling"
    assert payload["title_link"] == "http://localhost/forage/items/manual/#{item.id}"
    assert payload["text"] == "Render Hive links nicely."
    assert payload["footer"] =~ "Hive ·"
    assert payload["footer"] =~ "Feature request"
  end

  test "unfurl/1 skips organization-only feature requests" do
    user = user!()

    {:ok, item} =
      Repo.insert(%FeatureRequest{
        type: :feature_request,
        title: "Internal idea",
        description: "Internal only.",
        status: :open,
        visibility: :organization,
        user_id: user.id
      })

    assert SlackUnfurl.unfurl(uri("/forage/items/manual/#{item.id}")) == :skip
  end

  test "unfurl/1 skips when the manual item does not exist" do
    assert SlackUnfurl.unfurl(uri("/forage/items/manual/#{Ecto.UUID.generate()}")) == :skip
  end

  test "unfurl/1 skips unknown origins" do
    assert SlackUnfurl.unfurl(uri("/forage/items/bogus/abc")) == :skip
  end

  test "unfurl/1 skips when the path is not a forage item URL" do
    assert SlackUnfurl.unfurl(uri("/specs/1")) == :skip
  end
end
