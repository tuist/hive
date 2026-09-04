defmodule Hive.GitHub.WebhooksTest do
  use Hive.DataCase, async: true

  alias Hive.Audit.Activity
  alias Hive.Errors.SentryEvent
  alias Hive.GitHub.Webhooks
  alias Hive.Projects
  alias Hive.Repo

  @secret "webhook-secret"
  @body ~s({"action":"ping"})

  test "verifies a matching SHA-256 webhook signature" do
    assert Webhooks.verify_signature(@body, signature(@body, @secret), @secret) == :ok
  end

  test "rejects a signature generated with another secret" do
    assert Webhooks.verify_signature(@body, signature(@body, "other-secret"), @secret) ==
             {:error, :invalid_signature}
  end

  test "rejects a missing signature" do
    assert Webhooks.verify_signature(@body, nil, @secret) == {:error, :missing_signature}
  end

  test "resolves linked-project errors referenced by a merged pull request" do
    %{issue: issue, repository: repository} = linked_error_fixture()

    assert :ok =
             Webhooks.handle_event(
               "pull_request",
               pull_request_payload(repository, "#{HiveWeb.Endpoint.url()}/errors/#{issue.id}")
             )

    resolved = Repo.get!(Hive.Errors.Issue, issue.id)
    assert resolved.status == :resolved
    assert %DateTime{} = resolved.resolved_at

    assert [%Activity{} = activity] = Repo.all(Activity)
    assert activity.action == "error.resolved"
    assert activity.interface == "webhook"
    assert activity.target_id == issue.id
    assert activity.metadata["pull_request_url"] == "https://github.com/acme/widgets/pull/42"
  end

  test "ignores error links from another Hive project" do
    %{issue: issue, repository: repository} = linked_error_fixture()
    {:ok, other_project} = Projects.create_project(%{"name" => unique_name("Other")})

    {:ok, other_issue} =
      Hive.ErrorsHelpers.seed_issue(
        other_project,
        SentryEvent.parse(%{"message" => "other project boom"})
      )

    body = "#{HiveWeb.Endpoint.url()}/errors/#{other_issue.id}"
    assert :ok = Webhooks.handle_event("pull_request", pull_request_payload(repository, body))

    assert Repo.get!(Hive.Errors.Issue, issue.id).status == :unresolved
    assert Repo.get!(Hive.Errors.Issue, other_issue.id).status == :unresolved
    assert Repo.all(Activity) == []
  end

  test "ignores unmerged pull requests and links to another host" do
    %{issue: issue, repository: repository} = linked_error_fixture()
    foreign_body = "https://not-hive.example/errors/#{issue.id}"

    unmerged_payload =
      repository
      |> pull_request_payload("#{HiveWeb.Endpoint.url()}/errors/#{issue.id}")
      |> put_in(["pull_request", "merged"], false)

    assert :ok = Webhooks.handle_event("pull_request", unmerged_payload)

    assert :ok =
             Webhooks.handle_event("pull_request", pull_request_payload(repository, foreign_body))

    assert Repo.get!(Hive.Errors.Issue, issue.id).status == :unresolved
    assert Repo.all(Activity) == []
  end

  test "repeated deliveries preserve the original resolution timestamp" do
    %{issue: issue, repository: repository} = linked_error_fixture()
    payload = pull_request_payload(repository, "#{HiveWeb.Endpoint.url()}/errors/#{issue.id}")

    assert :ok = Webhooks.handle_event("pull_request", payload)
    first_resolution = Repo.get!(Hive.Errors.Issue, issue.id).resolved_at
    assert :ok = Webhooks.handle_event("pull_request", payload)

    assert Repo.get!(Hive.Errors.Issue, issue.id).resolved_at == first_resolution
    assert Repo.aggregate(Activity, :count) == 1
  end

  defp signature(body, secret) do
    digest =
      :hmac
      |> :crypto.mac(:sha256, secret, body)
      |> Base.encode16(case: :lower)

    "sha256=#{digest}"
  end

  defp linked_error_fixture do
    {:ok, project} = Projects.create_project(%{"name" => unique_name("Widgets")})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{
        "owner" => "acme",
        "name" => "widgets",
        "visibility" => "private"
      })

    {:ok, issue} =
      Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "boom"}))

    %{project: project, repository: repository, issue: issue}
  end

  defp pull_request_payload(repository, body) do
    %{
      "action" => "closed",
      "pull_request" => %{
        "body" => body,
        "html_url" => "https://github.com/acme/widgets/pull/42",
        "merged" => true,
        "number" => 42
      },
      "repository" => %{"full_name" => "#{repository.owner}/#{repository.name}"}
    }
  end

  defp unique_name(prefix), do: "#{prefix} #{System.unique_integer([:positive])}"
end
