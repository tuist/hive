defmodule Hive.Errors.LoggerHandlerTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Errors.LoggerHandler

  setup :verify_on_exit!

  describe "log/2 loop-break guards" do
    test "drops logs emitted from the ClickHouse driver" do
      reject(&Hive.Errors.record_event/2)

      event = %{
        level: :error,
        msg: {:string, "Ch.Connection failed to connect"},
        meta: %{mfa: {Ch.Connection, :handle_event, 4}, time: System.system_time(:microsecond)}
      }

      assert :ok = LoggerHandler.log(event, %{})
    end

    test "drops logs emitted from the ClickHouse Ecto adapter" do
      reject(&Hive.Errors.record_event/2)

      event = %{
        level: :error,
        msg: {:string, "adapter noise"},
        meta: %{
          mfa: {Ecto.Adapters.ClickHouse, :execute, 5},
          time: System.system_time(:microsecond)
        }
      }

      assert :ok = LoggerHandler.log(event, %{})
    end

    test "drops logs emitted from Hive's own ingest buffer" do
      reject(&Hive.Errors.record_event/2)

      event = %{
        level: :error,
        msg: {:string, "buffer flush failed"},
        meta: %{
          mfa: {Hive.Ingestion.Buffer, :handle_info, 2},
          time: System.system_time(:microsecond)
        }
      }

      assert :ok = LoggerHandler.log(event, %{})
    end

    test "drops crash reports whose exception is Ch.Error" do
      reject(&Hive.Errors.record_event/2)

      event = %{
        level: :error,
        msg: {:string, "CH server error"},
        meta: %{
          mfa: {Some.Caller, :run, 0},
          crash_reason: {%Ch.Error{code: 81, message: "Database does not exist"}, []},
          time: System.system_time(:microsecond)
        }
      }

      assert :ok = LoggerHandler.log(event, %{})
    end

    test "drops DBConnection.ConnectionError scoped to Hive.IngestRepo" do
      reject(&Hive.Errors.record_event/2)

      event = %{
        level: :error,
        msg: {:string, "pool timeout"},
        meta: %{
          mfa: {Some.Caller, :run, 0},
          crash_reason:
            {%DBConnection.ConnectionError{
               message: "[Elixir.Hive.IngestRepo] connection not available",
               reason: :queue_timeout
             }, []},
          time: System.system_time(:microsecond)
        }
      }

      assert :ok = LoggerHandler.log(event, %{})
    end

    test "does NOT drop DBConnection.ConnectionError from Hive.Repo (Postgres)" do
      # A real Postgres pool error is a separate problem and should be
      # recorded. Stub the self-project lookup so we can observe
      # whether `record_event` is invoked.
      {:ok, project} =
        Hive.Projects.create_project(%{
          "name" => "logger-handler-test-#{System.unique_integer([:positive])}"
        })

      stub(Hive.Errors.SelfMonitor, :self_project_id, fn -> project.id end)
      test_pid = self()

      expect(Hive.Errors, :record_event, fn _project, _event ->
        send(test_pid, :recorded)
        {:ok, %{}}
      end)

      event = %{
        level: :error,
        msg: {:string, "pool timeout"},
        meta: %{
          mfa: {Some.Caller, :run, 0},
          crash_reason:
            {%DBConnection.ConnectionError{
               message: "[Elixir.Hive.Repo] connection not available",
               reason: :queue_timeout
             }, []},
          time: System.system_time(:microsecond)
        }
      }

      assert :ok = LoggerHandler.log(event, %{})
      assert_received :recorded
    end
  end
end
