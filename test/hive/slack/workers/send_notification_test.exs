defmodule Hive.Slack.Workers.SendNotificationTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Accounts
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

    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    expect(API, :post_message, fn %Installation{id: id}, params ->
      assert id == installation.id
      assert params["channel"] == "C-notify"
      assert params["text"] == "New spec: Draft"
      assert [%{"text" => %{"text" => title}} | _] = params["blocks"]
      assert title =~ "##{spec.number}"

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
    {:ok, comment} = Specs.add_comment(spec, %{"body" => "Looks useful."}, user)

    expect(API, :post_message, fn %Installation{id: id}, params ->
      assert id == installation.id
      assert params["channel"] == "C-notify"
      assert params["text"] == "New spec comment: Draft"
      assert Enum.any?(params["blocks"], &match?(%{"text" => %{"text" => "Looks useful."}}, &1))

      {:ok, %{"ok" => true}}
    end)

    assert :ok =
             perform_job(SendNotification, %{
               "event" => "spec.comment.created",
               "comment_id" => comment.id
             })
  end

  test "perform/1 returns ok when no notification target is configured" do
    user = user!()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    reject(&API.post_message/2)

    assert :ok =
             perform_job(SendNotification, %{"event" => "spec.created", "spec_id" => spec.id})
  end
end
