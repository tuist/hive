defmodule Hive.Integrations.GitHubEventsTest do
  use Hive.DataCase, async: true

  alias Hive.Integrations
  alias Hive.Integrations.GitHubEvents
  alias Hive.Signals

  defp create_app_with_repo do
    suffix = System.unique_integer([:positive])
    owner = "owner-#{suffix}"
    repo = "repo-#{suffix}"

    {:ok, app} =
      Integrations.create_github_app(%{
        name: "Test App #{suffix}",
        webhook_secret: "secret",
        app_id: "123",
        private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
        installation_id: "456"
      })

    {:ok, _} = Integrations.add_github_repository(app, %{owner: owner, repo: repo})
    {app, "#{owner}/#{repo}"}
  end

  describe "verify_signature/3" do
    test "returns :ok for valid signature" do
      body = ~s({"action":"opened"})
      secret = "test_secret"

      expected =
        "sha256=" <>
          (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))

      assert :ok = GitHubEvents.verify_signature(body, expected, secret)
    end

    test "returns error for invalid signature" do
      assert {:error, :invalid_signature} =
               GitHubEvents.verify_signature("body", "sha256=wrong", "secret")
    end
  end

  describe "handle_event/2 for issues" do
    test "creates a signal when a new issue is opened in a monitored repo" do
      {_app, full_name} = create_app_with_repo()

      payload = %{
        "action" => "opened",
        "repository" => %{"full_name" => full_name},
        "issue" => %{
          "title" => "Bug: something is broken",
          "body" => "Steps to reproduce...",
          "number" => 42,
          "html_url" => "https://github.com/#{full_name}/issues/42",
          "created_at" => "2026-03-06T12:00:00Z",
          "user" => %{"login" => "contributor"}
        }
      }

      assert {:ok, signal} = GitHubEvents.handle_event("issues", payload)
      assert signal.title == "Bug: something is broken"
      assert signal.body == "Steps to reproduce..."
      assert signal.source == "github"
      assert signal.status == :new
      assert signal.source_author == "contributor"
      assert signal.source_channel == full_name
      assert signal.source_url == "https://github.com/#{full_name}/issues/42"
    end

    test "ignores issues from unmonitored repos" do
      create_app_with_repo()

      payload = %{
        "action" => "opened",
        "repository" => %{"full_name" => "other/repo"},
        "issue" => %{
          "title" => "Issue",
          "body" => "Body",
          "number" => 1,
          "html_url" => "https://github.com/other/repo/issues/1",
          "created_at" => "2026-03-06T12:00:00Z",
          "user" => %{"login" => "user"}
        }
      }

      assert :ignored = GitHubEvents.handle_event("issues", payload)
    end

    test "ignores non-opened issue actions" do
      assert :ignored = GitHubEvents.handle_event("issues", %{"action" => "closed"})
    end
  end

  describe "handle_event/2 for issue_comment" do
    test "adds a signal message when a comment is posted on a tracked issue" do
      {_app, full_name} = create_app_with_repo()
      issue_url = "https://github.com/#{full_name}/issues/42"

      {:ok, _signal} =
        Signals.create_signal(%{
          title: "Original issue",
          body: "Issue body",
          source: "github",
          source_url: issue_url,
          source_author: "author",
          source_channel: full_name
        })

      payload = %{
        "action" => "created",
        "repository" => %{"full_name" => full_name},
        "issue" => %{"html_url" => issue_url},
        "comment" => %{
          "body" => "I can reproduce this too",
          "html_url" => "#{issue_url}#issuecomment-123",
          "created_at" => "2026-03-06T13:00:00Z",
          "user" => %{"login" => "helper"}
        }
      }

      assert {:ok, message} = GitHubEvents.handle_event("issue_comment", payload)
      assert message.body == "I can reproduce this too"
      assert message.author == "helper"
    end

    test "ignores comments on issues that are not tracked as signals" do
      {_app, full_name} = create_app_with_repo()

      payload = %{
        "action" => "created",
        "repository" => %{"full_name" => full_name},
        "issue" => %{"html_url" => "https://github.com/#{full_name}/issues/999"},
        "comment" => %{
          "body" => "A comment",
          "html_url" => "https://github.com/#{full_name}/issues/999#issuecomment-1",
          "created_at" => "2026-03-06T13:00:00Z",
          "user" => %{"login" => "user"}
        }
      }

      assert :ignored = GitHubEvents.handle_event("issue_comment", payload)
    end

    test "ignores non-created comment actions" do
      assert :ignored = GitHubEvents.handle_event("issue_comment", %{"action" => "deleted"})
    end
  end

  describe "handle_event/2 for unknown events" do
    test "ignores unknown event types" do
      assert :ignored = GitHubEvents.handle_event("push", %{})
    end
  end
end
