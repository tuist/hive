defmodule Hive.GitHub.RepositoriesTest do
  use ExUnit.Case, async: true

  alias Hive.GitHub.Client.Config
  alias Hive.GitHub.Repositories

  describe "list_accessible_repositories/1" do
    test "returns not configured when GitHub App credentials are missing" do
      assert {:error, {:not_configured, missing}} =
               Repositories.list_accessible_repositories(config: %Config{})

      assert :app_id in missing
      assert :installation_id in missing
      assert :private_key in missing
    end

    test "lists every installation repository" do
      config = %Config{
        app_id: "123",
        installation_id: "456",
        private_key: "private-key",
        api_url: "https://api.github.test"
      }

      request = fn request ->
        assert request[:method] == :get

        assert request[:url] ==
                 "https://api.github.test/installation/repositories?per_page=100&page=1"

        headers = Map.new(request[:headers])

        assert headers["authorization"] == "Bearer installation-token"
        assert headers["accept"] == "application/vnd.github+json"

        {:ok,
         %{
           status: 200,
           body: %{
             "repositories" => [
               %{
                 "full_name" => "tuist/hive",
                 "name" => "hive",
                 "description" => "Domain orchestration"
               },
               %{
                 "full_name" => "tuist/tuist",
                 "name" => "tuist",
                 "description" => "Xcode tooling"
               }
             ]
           }
         }}
      end

      assert {:ok, [hive, tuist]} =
               Repositories.list_accessible_repositories(
                 config: config,
                 installation_token: "installation-token",
                 request: request
               )

      assert Repositories.full_name(hive) == "tuist/hive"
      assert hive.description == "Domain orchestration"
      assert Repositories.full_name(tuist) == "tuist/tuist"
    end

    test "returns GitHub API errors" do
      config = %Config{
        app_id: "123",
        installation_id: "456",
        private_key: "private-key",
        api_url: "https://api.github.test"
      }

      request = fn _request ->
        {:ok, %{status: 403, body: %{"message" => "Forbidden"}}}
      end

      assert {:error, {:unexpected_status, 403, %{"message" => "Forbidden"}}} =
               Repositories.list_accessible_repositories(
                 config: config,
                 installation_token: "installation-token",
                 request: request
               )
    end
  end
end
