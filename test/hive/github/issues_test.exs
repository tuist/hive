defmodule Hive.GitHub.IssuesTest do
  use ExUnit.Case, async: true

  alias Hive.GitHub.Client.Config
  alias Hive.GitHub.Issues

  defp config do
    %Config{
      app_id: "123",
      installation_id: "456",
      private_key: "private-key",
      api_url: "https://api.github.test"
    }
  end

  defp repository, do: %{owner: "tuist", name: "hive"}

  describe "list_open_issues/2" do
    test "returns not configured when GitHub App credentials are missing" do
      assert {:error, {:not_configured, missing}} =
               Issues.list_open_issues(repository(), config: %Config{})

      assert :app_id in missing
    end

    test "fetches open issues and ignores pull requests" do
      request = fn request ->
        assert request[:method] == :get

        assert request[:url] ==
                 "https://api.github.test/repos/tuist/hive/issues" <>
                   "?state=open&per_page=100&page=1&sort=updated&direction=desc"

        headers = Map.new(request[:headers])
        assert headers["authorization"] == "Bearer installation-token"

        {:ok,
         %{
           status: 200,
           body: [
             %{
               "number" => 42,
               "title" => "Add a thing",
               "body" => "Please add the thing.",
               "state" => "open",
               "html_url" => "https://github.com/tuist/hive/issues/42",
               "user" => %{"login" => "alice", "avatar_url" => "https://avatar/alice"},
               "labels" => [%{"name" => "bug", "color" => "ff0000"}],
               "comments" => 3,
               "created_at" => "2026-06-01T00:00:00Z",
               "updated_at" => "2026-06-02T00:00:00Z"
             },
             %{
               "number" => 43,
               "title" => "A PR",
               "pull_request" => %{"url" => "https://github.com/tuist/hive/pull/43"}
             }
           ]
         }}
      end

      assert {:ok, [issue]} =
               Issues.list_open_issues(repository(),
                 config: config(),
                 installation_token: "installation-token",
                 request: request
               )

      assert issue.number == 42
      assert issue.title == "Add a thing"
      assert issue.user_login == "alice"
      assert issue.labels == [%{name: "bug", color: "ff0000"}]
      assert issue.comments == 3
    end

    test "returns GitHub API errors" do
      request = fn _request ->
        {:ok, %{status: 404, body: %{"message" => "Not Found"}}}
      end

      assert {:error, {:unexpected_status, 404, %{"message" => "Not Found"}}} =
               Issues.list_open_issues(repository(),
                 config: config(),
                 installation_token: "installation-token",
                 request: request
               )
    end
  end

  describe "list_comments/3" do
    test "fetches issue comments" do
      request = fn request ->
        assert request[:method] == :get

        assert request[:url] ==
                 "https://api.github.test/repos/tuist/hive/issues/42/comments" <>
                   "?per_page=100&page=1"

        {:ok,
         %{
           status: 200,
           body: [
             %{
               "id" => 1,
               "body" => "Looks useful.",
               "html_url" => "https://github.com/tuist/hive/issues/42#issuecomment-1",
               "user" => %{"login" => "octo", "avatar_url" => "https://avatar/octo"},
               "created_at" => "2026-06-01T00:00:00Z",
               "updated_at" => "2026-06-01T00:00:00Z"
             }
           ]
         }}
      end

      assert {:ok, [comment]} =
               Issues.list_comments(repository(), 42,
                 config: config(),
                 installation_token: "installation-token",
                 request: request
               )

      assert comment.id == 1
      assert comment.body == "Looks useful."
      assert comment.user_login == "octo"
      assert comment.user_avatar_url == "https://avatar/octo"
    end

    test "returns GitHub API errors for comments" do
      request = fn _request ->
        {:ok, %{status: 404, body: %{"message" => "Not Found"}}}
      end

      assert {:error, {:unexpected_status, 404, %{"message" => "Not Found"}}} =
               Issues.list_comments(repository(), 42,
                 config: config(),
                 installation_token: "installation-token",
                 request: request
               )
    end
  end
end
