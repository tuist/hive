defmodule Hive.Errors.Workers.IngestEnvelopeTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Errors
  alias Hive.Errors.Workers.IngestEnvelope
  alias Hive.Projects

  setup :verify_on_exit!

  setup do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)
    stub(Hive.IngestRepo, :insert_all, fn _table, rows -> {length(rows), nil} end)

    {:ok, project} = Projects.create_project(%{"name" => "Widgets"})
    {:ok, project: project}
  end

  test "records each event item and skips non-event items", %{project: project} do
    payload_one = ~s({"event_id":"a","message":"boom"})
    payload_two = ~s({"event_id":"b","message":"crash"})
    session_payload = ~s({"sid":"s1"})

    body =
      [
        ~s({}),
        ~s({"type":"event","length":#{byte_size(payload_one)}}),
        payload_one,
        ~s({"type":"session","length":#{byte_size(session_payload)}}),
        session_payload,
        ~s({"type":"event","length":#{byte_size(payload_two)}}),
        payload_two
      ]
      |> Enum.join("\n")

    assert :ok =
             perform_job(IngestEnvelope, %{
               "project_id" => project.id,
               "body" => body
             })

    issues = Errors.list_issues(project_id: project.id)
    assert length(issues) == 2
  end

  test "cancels when the project no longer exists" do
    body = ~s({}\n{"type":"event"}\n{"level":"error"})

    assert {:cancel, :project_not_found} =
             perform_job(IngestEnvelope, %{
               "project_id" => "00000000-0000-0000-0000-000000000000",
               "body" => body
             })
  end
end
