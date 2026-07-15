defmodule Hive.Slack.Workers.SendNotificationTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Accounts
  alias Hive.Slack
  alias Hive.Slack.API
  alias Hive.Slack.Installation
  alias Hive.Slack.Workers.SendNotification
  alias Hive.Specs

  defp user! do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "alice-#{suffix}@example.com",
        provider: "test",
        provider_uid: "alice-#{suffix}@example.com"
      })

    user
  end

  defp installation!(attrs) do
    suffix = System.unique_integer([:positive])

    attrs =
      Map.merge(
        %{
          team_id: "T#{suffix}",
          team_name: "Workspace #{suffix}",
          bot_token: "xoxb-#{suffix}",
          installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        },
        attrs
      )

    {:ok, installation} =
      %Installation{}
      |> Installation.changeset(attrs)
      |> Repo.insert()

    installation
  end

  test "enqueue/2 inserts a job when the event is enabled" do
    installation!(%{
      notification_channel_id: "C-notify",
      notification_events: ["spec.created"]
    })

    assert {:ok, _job} = SendNotification.enqueue("spec.created", %{"spec_id" => "s1"})

    assert_enqueued(
      worker: SendNotification,
      args: %{"event" => "spec.created", "spec_id" => "s1"}
    )
  end

  test "enqueue/2 skips when the event has no notification targets" do
    assert :skipped = SendNotification.enqueue("spec.created", %{"spec_id" => "s1"})
    assert all_enqueued() == []
  end

  test "perform/1 posts a new spec notification" do
    user = user!()

    installation =
      installation!(%{
        notification_channel_id: "C-notify",
        notification_events: ["spec.created"]
      })

    body = "**Initial proposal.**\n\n- Keep the behavior focused."
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => body}, user)

    expect(API, :post_message, fn %Installation{id: id}, params ->
      assert id == installation.id
      assert params["channel"] == "C-notify"
      assert params["text"] == "New spec: Draft"

      assert [
               %{"type" => "header", "text" => %{"text" => "Draft"}},
               %{"type" => "markdown", "text" => ^body},
               %{"type" => "section", "fields" => fields},
               %{"type" => "context", "elements" => [%{"text" => "New spec / Hive"}]},
               %{
                 "type" => "actions",
                 "elements" => [%{"url" => url, "text" => %{"text" => "Open in Hive"}}]
               }
             ] = params["blocks"]

      assert Enum.any?(fields, &(&1["text"] == "- Spec ##{spec.number}"))
      assert Enum.any?(fields, &(&1["text"] == "- Status: draft"))
      assert url == HiveWeb.Endpoint.url() <> "/specs/#{spec.number}"

      {:ok, %{"ok" => true}}
    end)

    assert :ok =
             perform_job(SendNotification, %{
               "event" => "spec.created",
               "spec_id" => spec.id
             })
  end

  test "perform/1 posts a new spec comment notification" do
    user = user!()

    installation =
      installation!(%{
        notification_channel_id: "C-notify",
        notification_events: ["spec.comment.created"]
      })

    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    body = """
    **Addressed as suggested**

    - Exact analytics on a lossy pipeline
    - `bytes_wired` is counted at stream end
    """

    description = String.trim(body)

    {:ok, comment} = Specs.add_comment(spec, %{"body" => body}, user)

    expect(API, :post_message, fn %Installation{id: id}, params ->
      assert id == installation.id
      assert params["channel"] == "C-notify"
      assert params["text"] == "New spec comment: Draft"

      assert [
               %{"type" => "header", "text" => %{"text" => "Draft"}},
               %{"type" => "markdown", "text" => ^description},
               %{"type" => "section", "fields" => fields},
               %{
                 "type" => "context",
                 "elements" => [%{"text" => "New spec comment / Hive"}]
               },
               %{
                 "type" => "actions",
                 "elements" => [%{"url" => url, "text" => %{"text" => "Open in Hive"}}]
               }
             ] = params["blocks"]

      assert Enum.any?(fields, &(&1["text"] == "- Spec ##{spec.number}"))
      assert url == HiveWeb.Endpoint.url() <> "/specs/#{spec.number}"

      {:ok, %{"ok" => true}}
    end)

    assert :ok =
             perform_job(SendNotification, %{
               "event" => "spec.comment.created",
               "comment_id" => comment.id
             })
  end

  test "perform/1 posts a spec review request notification with linked commenters" do
    requester = user!()
    reviewer = user!()

    installation =
      installation!(%{
        notification_channel_id: "C-notify",
        notification_events: ["spec.review.requested"]
      })

    {:ok, _slack_user} =
      Slack.upsert_user(installation, %{
        slack_user_id: "U-reviewer",
        email: reviewer.email,
        name: "reviewer"
      })

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Reviewable draft",
          "body" => "Initial proposal.",
          "summary" => "Tighten the sign-in flow."
        },
        requester
      )

    {:ok, _comment} = Specs.add_comment(spec, %{"body" => "Check the error states."}, reviewer)

    expect(API, :post_message, fn %Installation{id: id}, params ->
      assert id == installation.id
      assert params["channel"] == "C-notify"
      assert params["text"] == "Review requested for spec ##{spec.number}: Reviewable draft"

      blocks = params["blocks"]
      assert Enum.any?(blocks, &block_text_contains?(&1, "*Review requested:*"))
      assert Enum.any?(blocks, &block_text_contains?(&1, "Tighten the sign-in flow."))
      assert Enum.any?(blocks, &block_text_contains?(&1, "<@U-reviewer>"))
      assert Enum.any?(blocks, &block_text_contains?(&1, "**Review focus:**"))

      assert Enum.any?(blocks, fn
               %{"type" => "actions", "elements" => [%{"text" => %{"text" => "Open spec"}}]} ->
                 true

               _block ->
                 false
             end)

      {:ok, %{"ok" => true}}
    end)

    assert :ok =
             perform_job(SendNotification, %{
               "event" => "spec.review.requested",
               "spec_id" => spec.id,
               "requester_id" => requester.id
             })
  end

  test "perform/1 returns ok when no notification target is configured" do
    user = user!()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    reject(&API.post_message/2)

    assert :ok =
             perform_job(SendNotification, %{"event" => "spec.created", "spec_id" => spec.id})
  end

  defp block_text_contains?(%{"text" => %{"text" => text}}, needle),
    do: String.contains?(text, needle)

  defp block_text_contains?(%{"text" => text}, needle) when is_binary(text),
    do: String.contains?(text, needle)

  defp block_text_contains?(%{"elements" => elements}, needle) when is_list(elements) do
    Enum.any?(elements, &block_text_contains?(&1, needle))
  end

  defp block_text_contains?(_block, _needle), do: false
end
