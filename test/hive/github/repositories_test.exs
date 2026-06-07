defmodule Hive.GitHub.RepositoriesTest do
  use ExUnit.Case, async: true

  alias Hive.GitHub.Repositories
  alias Hive.GitHub.Repositories.Config

  describe "search_accessible_repositories/2" do
    test "returns not configured when GitHub App credentials are missing" do
      assert {:error, {:not_configured, missing}} =
               Repositories.search_accessible_repositories("hive", config: %Config{})

      assert :app_id in missing
      assert :installation_id in missing
      assert :private_key in missing
    end

    test "lists installation repositories and filters them by full name" do
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
                 "description" => "Product orchestration"
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

      assert {:ok, [repository]} =
               Repositories.search_accessible_repositories("hiv",
                 config: config,
                 installation_token: "installation-token",
                 request: request
               )

      assert Repositories.full_name(repository) == "tuist/hive"
      assert repository.description == "Product orchestration"
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
               Repositories.search_accessible_repositories("hive",
                 config: config,
                 installation_token: "installation-token",
                 request: request
               )
    end
  end
end
