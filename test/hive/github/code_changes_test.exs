defmodule Hive.GitHub.CodeChangesTest do
  use ExUnit.Case, async: true

  alias Hive.Domains.GitHubRepository
  alias Hive.GitHub.Client.Config
  alias Hive.GitHub.CodeChanges

  defp config do
    %Config{
      app_id: "123",
      installation_id: "456",
      private_key: "private-key",
      api_url: "https://api.github.test"
    }
  end

  defp repository, do: %GitHubRepository{owner: "tuist", name: "hive"}

  test "fetches an exact default-branch snapshot without exposing the installation token" do
    test_pid = self()

    request = fn request ->
      send(test_pid, {:request, request})

      case request[:url] do
        "https://api.github.test/repos/tuist/hive" ->
          {:ok, %{status: 200, body: %{"default_branch" => "main"}}}

        "https://api.github.test/repos/tuist/hive/git/ref/heads/main" ->
          {:ok, %{status: 200, body: %{"object" => %{"sha" => "commit-sha"}}}}

        "https://api.github.test/repos/tuist/hive/git/commits/commit-sha" ->
          {:ok, %{status: 200, body: %{"tree" => %{"sha" => "tree-sha"}}}}

        "https://api.github.test/repos/tuist/hive/tarball/commit-sha" ->
          {:ok, %{status: 200, body: "compressed-source"}}
      end
    end

    assert {:ok, source} =
             CodeChanges.fetch_source(repository(),
               config: config(),
               installation_token: "installation-token",
               request: request
             )

    assert source == %{
             archive: "compressed-source",
             base_branch: "main",
             base_sha: "commit-sha",
             base_tree_sha: "tree-sha"
           }

    for _index <- 1..4 do
      assert_receive {:request, request}
      assert {"authorization", "Bearer installation-token"} in request[:headers]
      refute inspect(request) =~ "private-key"
    end
  end

  test "turns changed files into a commit, branch, and pull request" do
    test_pid = self()

    request = fn request ->
      send(test_pid, {:request, request})

      case request[:url] do
        "https://api.github.test/repos/tuist/hive/git/blobs" ->
          {:ok, %{status: 201, body: %{"sha" => "blob-sha"}}}

        "https://api.github.test/repos/tuist/hive/git/trees" ->
          {:ok, %{status: 201, body: %{"sha" => "new-tree-sha"}}}

        "https://api.github.test/repos/tuist/hive/git/commits" ->
          {:ok, %{status: 201, body: %{"sha" => "new-commit-sha"}}}

        "https://api.github.test/repos/tuist/hive/git/refs" ->
          {:ok, %{status: 201, body: %{"ref" => "refs/heads/hive/fix"}}}

        "https://api.github.test/repos/tuist/hive/pulls" ->
          {:ok,
           %{
             status: 201,
             body: %{
               "number" => 42,
               "title" => "fix(forage): address alert",
               "html_url" => "https://github.example/tuist/hive/pull/42"
             }
           }}
      end
    end

    source = %{base_branch: "main", base_sha: "base-sha", base_tree_sha: "base-tree"}

    changes = [
      %{path: "lib/fixed.ex", content: "fixed", mode: "100644", deleted?: false},
      %{path: "lib/old.ex", content: nil, mode: "100644", deleted?: true}
    ]

    attrs = %{
      branch: "hive/fix",
      commit_message: "fix(forage): address alert",
      title: "fix(forage): address alert",
      body: "## What changed\n\nFixed it."
    }

    assert {:ok, pull_request} =
             CodeChanges.publish(repository(), source, changes, attrs,
               config: config(),
               installation_token: "installation-token",
               request: request
             )

    assert pull_request.number == 42
    assert pull_request.url == "https://github.example/tuist/hive/pull/42"

    requests = for _index <- 1..5, do: receive_request()
    blob_request = Enum.find(requests, &String.ends_with?(&1[:url], "/git/blobs"))
    assert blob_request[:json]["content"] == Base.encode64("fixed")
    assert blob_request[:json]["encoding"] == "base64"

    tree_request = Enum.find(requests, &String.ends_with?(&1[:url], "/git/trees"))
    assert tree_request[:json]["base_tree"] == "base-tree"

    assert %{"path" => "lib/old.ex", "sha" => nil} =
             Enum.find(tree_request[:json]["tree"], &(&1["path"] == "lib/old.ex"))

    pull_request = Enum.find(requests, &String.ends_with?(&1[:url], "/pulls"))
    assert pull_request[:json]["head"] == "hive/fix"
    assert pull_request[:json]["base"] == "main"
  end

  defp receive_request do
    receive do
      {:request, request} -> request
    after
      1_000 -> flunk("expected GitHub request")
    end
  end
end
