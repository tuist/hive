defmodule Hive.ForageTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.Forage
  alias Hive.Products

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

  defp user_with_email(prefix) do
    suffix = unique()
    user(%{email: "#{prefix}-#{suffix}@example.com", provider_uid: "#{prefix}-#{suffix}"})
  end

  defp product_with_repo!(opts) do
    suffix = unique()
    visibility = Keyword.get(opts, :visibility, "public")
    repo_visibility = Keyword.get(opts, :repo_visibility, "public")

    {:ok, product} =
      Products.create_product(%{
        name: "forage-#{suffix}",
        visibility: visibility,
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo#{suffix}",
        github_repository_visibility: repo_visibility
      })

    product
  end

  defp unique, do: System.unique_integer([:positive])

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
               :github_issues,
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

    test "github_issues is hidden from guests when no public/public pair exists" do
      product_with_repo!(visibility: "private", repo_visibility: "public")

      refute Forage.can_access?(Forage.get_source!(:github_issues), nil)
    end

    test "github_issues is visible to guests when at least one public/public pair exists" do
      product_with_repo!(visibility: "public", repo_visibility: "public")

      assert Forage.can_access?(Forage.get_source!(:github_issues), nil)
    end

    test "github_issues is hidden from guests when the repo is private even if the product is public" do
      product_with_repo!(visibility: "public", repo_visibility: "private")

      refute Forage.can_access?(Forage.get_source!(:github_issues), nil)
    end

    test "github_issues is visible to members even when no products are connected" do
      stub(Auth, :member?, fn _user -> true end)

      assert Forage.can_access?(
               Forage.get_source!(:github_issues),
               user_with_email("forage-member")
             )
    end
  end

  describe "accessible_products_with_repositories/1" do
    test "returns no pairs for a guest when every pair is gated by a private side" do
      product_with_repo!(visibility: "public", repo_visibility: "private")

      assert Forage.accessible_products_with_repositories(nil) == []
    end

    test "returns every pair to a member regardless of visibility" do
      stub(Auth, :member?, fn _user -> true end)

      product = product_with_repo!(visibility: "private", repo_visibility: "private")

      assert [{%{name: name}, %{owner: owner, name: repo_name}}] =
               Forage.accessible_products_with_repositories(user_with_email("forage-pairs"))

      assert name == product.name
      assert owner == hd(product.github_repositories).owner
      assert repo_name == hd(product.github_repositories).name
    end

    test "skips products without a connected repository" do
      {:ok, _} = Products.create_product(%{name: "forage-no-repo-#{unique()}"})

      assert Forage.accessible_products_with_repositories(nil) == []
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
