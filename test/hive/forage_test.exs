defmodule Hive.ForageTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Forage

  defp user(attrs \\ %{}) do
    {:ok, user} =
      Accounts.upsert_from_auth(
        Map.merge(
          %{email: "alice@example.com", provider: "test", provider_uid: "alice"},
          attrs
        )
      )

    user
  end

  test "visible_sources hides organization-only forage sources from guests" do
    assert Forage.visible_sources(nil) |> Enum.map(& &1.id) == [
             :feature_requests,
             :bug_reports,
             :feedback
           ]
  end

  test "visible_sources includes organization-only forage sources for members" do
    assert Forage.visible_sources(user()) |> Enum.map(& &1.id) == [
             :feature_requests,
             :bug_reports,
             :feedback,
             :grafana_alerts
           ]
  end

  test "create_feature_request binds requester details from the signed-in user" do
    user = user()

    {:ok, feature_request} =
      Forage.create_feature_request(
        %{"title" => "GitHub sign-in", "description" => "Let requesters sign in with GitHub."},
        user
      )

    assert feature_request.requester_email == "alice@example.com"
    assert feature_request.user_id == user.id
    assert feature_request.visibility == :public
    assert feature_request.status == :open
  end
end
