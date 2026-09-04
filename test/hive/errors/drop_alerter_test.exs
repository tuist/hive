defmodule Hive.Errors.DropAlerterTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Errors.DropAlerter

  setup :verify_on_exit!

  # Spin up an isolated GenServer per-test so cases don't share state.
  setup context do
    name = :"drop_alerter_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      start_supervised(
        {DropAlerter,
         [
           name: name,
           flush_interval_ms: 60_000
         ]}
      )

    # Share this test's SQL Sandbox connection with the alerter process
    # so its `Repo.one` for the installation can use the same ownership.
    :ok = Ecto.Adapters.SQL.Sandbox.allow(Hive.Repo, self(), pid)
    Mimic.allow(Hive.Slack.API, self(), pid)

    {:ok, Map.merge(context, %{alerter: name, pid: pid})}
  end

  describe "coalescing" do
    test "coalesces repeated flush failures into a single Slack post",
         %{pid: pid} = ctx do
      test_pid = self()

      expect(Hive.Slack.API, :post_message, fn _installation, payload ->
        send(test_pid, {:posted, payload})
        {:ok, %{}}
      end)

      make_installation!()
      System.put_env("HIVE_ALERTS_SLACK_CHANNEL_ID", "C_TEST_CHANNEL")
      on_exit(fn -> System.delete_env("HIVE_ALERTS_SLACK_CHANNEL_ID") end)

      Enum.each(1..25, fn _ ->
        GenServer.cast(
          pid,
          {:report, :flush_failure,
           %{name: "Hive.Errors.Event.Buffer", byte_size: 1_024, sample: "Ch.Error 81"}}
        )
      end)

      # Cast is async — sync via a call to make sure all casts landed.
      _ = :sys.get_state(pid)

      :ok = DropAlerter.flush(ctx.alerter)

      assert_receive {:posted, payload}, 1_000
      # Mobile-notification fallback text carries the count + buffer.
      assert payload.text =~ "HIVE INGEST BROKEN"
      assert payload.text =~ "25"
      assert payload.text =~ "Hive.Errors.Event.Buffer"

      # Alert visual: red attachment, header, @channel ping, danger button.
      [attachment] = payload.attachments
      assert attachment.color == "#E01E5A"
      blocks = attachment.blocks
      assert Enum.any?(blocks, &match?(%{type: "header"}, &1))
      body_text = Enum.map_join(blocks, " ", &extract_text/1)
      assert body_text =~ "<!channel>"
      assert body_text =~ "dropped on the floor"

      # Channel and unfurl hygiene.
      assert payload.channel == "C_TEST_CHANNEL"
      assert payload.unfurl_links == false
      assert payload.unfurl_media == false

      refute_receive {:posted, _}, 100
    end

    test "resets the bucket after flushing", %{pid: pid} = ctx do
      test_pid = self()

      expect(Hive.Slack.API, :post_message, 2, fn _installation, payload ->
        send(test_pid, {:posted, payload})
        {:ok, %{}}
      end)

      make_installation!()
      System.put_env("HIVE_ALERTS_SLACK_CHANNEL_ID", "C_TEST_CHANNEL")
      on_exit(fn -> System.delete_env("HIVE_ALERTS_SLACK_CHANNEL_ID") end)

      GenServer.cast(pid, {:report, :ingest_failure, %{sample: "%Postgrex.Error{...}"}})
      _ = :sys.get_state(pid)
      :ok = DropAlerter.flush(ctx.alerter)

      assert_receive {:posted, payload1}, 1_000
      assert payload1.text =~ "HIVE INGEST BROKEN"

      # Second window with new reports produces its own post.
      GenServer.cast(pid, {:report, :ingest_failure, %{sample: "different"}})
      _ = :sys.get_state(pid)
      :ok = DropAlerter.flush(ctx.alerter)

      assert_receive {:posted, payload2}, 1_000
      assert payload2.text =~ "HIVE INGEST BROKEN"
    end
  end

  describe "fallbacks" do
    test "falls back to a Logger.warning on :hive_alerts when no channel is configured",
         %{pid: pid} = ctx do
      System.delete_env("HIVE_ALERTS_SLACK_CHANNEL_ID")

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          GenServer.cast(
            pid,
            {:report, :flush_failure, %{name: "X.Buffer", byte_size: 512, sample: "boom"}}
          )

          _ = :sys.get_state(pid)
          :ok = DropAlerter.flush(ctx.alerter)
        end)

      assert log =~ "hive_alerts"
      assert log =~ "HIVE INGEST BROKEN"
      assert log =~ "no_channel_configured"
    end

    test "falls back to a Logger.warning when no Slack installation exists",
         %{pid: pid} = ctx do
      # Clear any pre-existing installations that leaked into the test
      # database outside sandbox rollback, so the alerter's Repo.one
      # actually returns nil.
      Hive.Repo.delete_all(Hive.Slack.Installation)
      System.put_env("HIVE_ALERTS_SLACK_CHANNEL_ID", "C_TEST_CHANNEL")
      on_exit(fn -> System.delete_env("HIVE_ALERTS_SLACK_CHANNEL_ID") end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          GenServer.cast(
            pid,
            {:report, :flush_failure, %{name: "X.Buffer", byte_size: 512, sample: "boom"}}
          )

          _ = :sys.get_state(pid)
          :ok = DropAlerter.flush(ctx.alerter)
        end)

      assert log =~ "hive_alerts"
      assert log =~ "no_slack_installation"
    end

    test "falls back to Logger.warning when Slack post itself fails",
         %{pid: pid} = ctx do
      make_installation!()
      System.put_env("HIVE_ALERTS_SLACK_CHANNEL_ID", "C_TEST_CHANNEL")
      on_exit(fn -> System.delete_env("HIVE_ALERTS_SLACK_CHANNEL_ID") end)

      expect(Hive.Slack.API, :post_message, fn _installation, _params ->
        {:error, :slack_api_error}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          GenServer.cast(
            pid,
            {:report, :flush_failure, %{name: "X.Buffer", byte_size: 512, sample: "boom"}}
          )

          _ = :sys.get_state(pid)
          :ok = DropAlerter.flush(ctx.alerter)
        end)

      assert log =~ "hive_alerts"
      assert log =~ ":slack_api_error"
    end
  end

  describe "telemetry" do
    test "emits [:hive, :errors, :ingest, :dropped] on each flush",
         %{pid: pid} = ctx do
      System.delete_env("HIVE_ALERTS_SLACK_CHANNEL_ID")
      handler_id = "test-handler-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:hive, :errors, :ingest, :dropped],
        fn _event, measurements, meta, _ ->
          send(test_pid, {:telemetry, measurements, meta})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      GenServer.cast(
        pid,
        {:report, :flush_failure, %{name: "X.Buffer", byte_size: 100, sample: "s"}}
      )

      GenServer.cast(
        pid,
        {:report, :flush_failure, %{name: "X.Buffer", byte_size: 100, sample: "s"}}
      )

      _ = :sys.get_state(pid)
      :ok = DropAlerter.flush(ctx.alerter)

      assert_receive {:telemetry, %{count: 2}, %{reason: :flush_failure}}, 1_000
    end
  end

  defp extract_text(%{text: %{text: t}}) when is_binary(t), do: t

  defp extract_text(%{fields: fields}) when is_list(fields),
    do: Enum.map_join(fields, " ", & &1.text)

  defp extract_text(_), do: ""

  defp make_installation! do
    {:ok, installation} =
      %Hive.Slack.Installation{}
      |> Ecto.Changeset.change(%{
        team_id: "T_TEST_#{System.unique_integer([:positive])}",
        team_name: "test-workspace",
        bot_token: "xoxb-test",
        bot_user_id: "U_BOT",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Hive.Repo.insert()

    installation
  end
end
