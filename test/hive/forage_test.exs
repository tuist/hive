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

  describe "get_source!/1" do
    test "returns the source with the given id" do
      assert Forage.get_source!(:feature_requests).id == :feature_requests
    end

    test "raises for an unknown source" do
      assert_raise ArgumentError, ~r/unknown forage source/, fn ->
        Forage.get_source!(:nope)
      end
    end
  end

  describe "visible_sources/1" do
    test "hides organization-only forage sources from guests" do
      assert Forage.visible_sources(nil) |> Enum.map(& &1.id) == [
               :feature_requests,
               :bug_reports,
               :feedback
             ]
    end

    test "includes organization-only forage sources for members" do
      assert Forage.visible_sources(user()) |> Enum.map(& &1.id) == [
               :feature_requests,
               :bug_reports,
               :feedback,
               :grafana_alerts
             ]
    end
  end

  describe "can_access?/2" do
    test "public sources are readable by guests" do
      assert Forage.can_access?(Forage.get_source!(:feature_requests), nil)
    end

    test "organization sources are hidden from guests" do
      refute Forage.can_access?(Forage.get_source!(:grafana_alerts), nil)
    end

    test "organization sources are readable by members" do
      assert Forage.can_access?(Forage.get_source!(:grafana_alerts), user())
    end
  end

  describe "can_create?/2" do
    test "guests cannot create on a public creatable source" do
      refute Forage.can_create?(Forage.get_source!(:feature_requests), nil)
    end

    test "members can create on a public creatable source" do
      assert Forage.can_create?(Forage.get_source!(:feature_requests), user())
    end

    test "nobody can create on a non-creatable source" do
      refute Forage.can_create?(Forage.get_source!(:grafana_alerts), user())
    end
  end

  describe "change_feature_request/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = Forage.change_feature_request()
    end

    test "is valid for sound attributes" do
      changeset =
        Forage.change_feature_request(%Hive.Forage.FeatureRequest{}, %{
          "title" => "A title",
          "description" => "A description that is long enough."
        })

      assert changeset.valid?
    end
  end

  describe "create_feature_request/2" do
    test "associates the request with the signed-in user" do
      user = user()

      {:ok, feature_request} =
        Forage.create_feature_request(
          %{"title" => "GitHub sign-in", "description" => "Let requesters sign in with GitHub."},
          user
        )

      assert feature_request.user_id == user.id
      assert feature_request.visibility == :public
      assert feature_request.status == :open
    end

    test "returns an error changeset for invalid attributes" do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Forage.create_feature_request(%{"title" => "", "description" => "short"}, user())
    end
  end

  describe "list_feature_requests/0" do
    test "preloads the requesting user" do
      user = user()

      {:ok, _} =
        Forage.create_feature_request(
          %{"title" => "GitHub sign-in", "description" => "Let requesters sign in with GitHub."},
          user
        )

      assert [feature_request] = Forage.list_feature_requests()
      assert feature_request.user.id == user.id
      assert feature_request.user.email == "alice@example.com"
    end
  end
end
