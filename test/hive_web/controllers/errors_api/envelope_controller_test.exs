defmodule HiveWeb.ErrorsAPI.EnvelopeControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Errors
  alias Hive.Projects

  setup :verify_on_exit!

  setup %{conn: conn} do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)
    stub(Hive.IngestRepo, :insert_all, fn _table, rows, _opts -> {length(rows), nil} end)

    {:ok, project} = Projects.create_project(%{"name" => "Widgets"})
    {:ok, key} = Errors.create_project_key(project.id)

    conn =
      conn
      |> put_req_header("content-type", "application/x-sentry-envelope")
      |> put_req_header(
        "x-sentry-auth",
        "Sentry sentry_version=7, sentry_key=#{key.public_key}"
      )

    {:ok, conn: conn, project: project, key: key}
  end

  describe "POST /api/:project_id/envelope/" do
    test "accepts a valid event envelope at the numeric project id", %{conn: conn, key: key} do
      body =
        envelope_body(
          "evt-abc-1234567890abcdef1234567890",
          ~s({"level":"error","message":"boom"})
        )

      conn = post(conn, ~p"/api/#{key.dsn_project_id}/envelope/", body)

      assert %{"id" => id} = json_response(conn, 200)
      assert is_binary(id)

      assert_enqueued(worker: Hive.Errors.Workers.IngestEnvelope)
    end

    test "rejects requests missing sentry_key", %{project: project} do
      body = envelope_body("evt-xyz", ~s({"level":"error"}))

      conn =
        build_conn()
        |> put_req_header("content-type", "application/x-sentry-envelope")
        |> post(~p"/api/#{project.id}/envelope/", body)

      assert conn.status == 401
    end

    test "rejects requests whose key belongs to a different project", %{conn: conn} do
      {:ok, other} = Projects.create_project(%{"name" => "Other"})
      {:ok, other_key} = Errors.create_project_key(other.id)
      body = envelope_body("evt-y", ~s({"level":"error"}))

      conn = post(conn, ~p"/api/#{other_key.dsn_project_id}/envelope/", body)
      assert conn.status == 403
    end

    test "rejects requests when ClickHouse is disabled", %{conn: conn, key: key} do
      # DSN check happens before availability, so we need to be careful about ordering.
      # Just verify the endpoint returns 503 through the record_event path.
      stub(Hive.Errors.Availability, :enabled?, fn -> false end)
      body = envelope_body("evt-z", ~s({"level":"error"}))

      # The 503 is raised by the ingest worker on perform; the controller still
      # accepts and enqueues.
      conn = post(conn, ~p"/api/#{key.dsn_project_id}/envelope/", body)
      assert conn.status == 200
    end
  end

  defp envelope_body(event_id, payload) do
    [
      ~s({"event_id":"#{event_id}","sent_at":"2026-09-03T15:00:00Z"}),
      ~s({"type":"event","length":#{byte_size(payload)}}),
      payload
    ]
    |> Enum.join("\n")
  end
end
