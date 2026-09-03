defmodule Hive.ErrorsTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Errors
  alias Hive.Errors.Issue
  alias Hive.Errors.ProjectKey
  alias Hive.Errors.SentryEvent
  alias Hive.Projects

  setup :verify_on_exit!

  setup do
    stub(Hive.IngestRepo, :insert_all, fn _table, rows -> {length(rows), nil} end)

    stub(Hive.Errors.Availability, :enabled?, fn -> true end)

    {:ok, project} = Projects.create_project(%{"name" => "Widgets"})
    {:ok, project: project}
  end

  describe "record_event/2" do
    test "creates a new issue and increments the count on repeat events", %{project: project} do
      event =
        SentryEvent.parse(%{
          "message" => "widget went sideways",
          "exception" => %{
            "values" => [
              %{
                "type" => "WidgetError",
                "value" => "sideways",
                "stacktrace" => %{
                  "frames" => [
                    %{"function" => "explode/0", "in_app" => true}
                  ]
                }
              }
            ]
          }
        })

      assert {:ok, %Issue{id: id, event_count: 1}} = Errors.record_event(project, event)
      assert {:ok, %Issue{id: ^id, event_count: 2}} = Errors.record_event(project, event)
      assert {:ok, %Issue{id: ^id, event_count: 3}} = Errors.record_event(project, event)
    end

    test "different fingerprints produce distinct issues", %{project: project} do
      a = SentryEvent.parse(%{"exception" => %{"values" => [%{"type" => "A"}]}})
      b = SentryEvent.parse(%{"exception" => %{"values" => [%{"type" => "B"}]}})

      {:ok, issue_a} = Errors.record_event(project, a)
      {:ok, issue_b} = Errors.record_event(project, b)

      refute issue_a.id == issue_b.id
    end

    test "returns :not_configured when ClickHouse is disabled", %{project: project} do
      stub(Hive.Errors.Availability, :enabled?, fn -> false end)

      assert {:error, :not_configured} =
               Errors.record_event(project, SentryEvent.parse(%{"message" => "hi"}))
    end
  end

  describe "list_issues/1" do
    test "filters by project and status", %{project: project} do
      {:ok, other} = Projects.create_project(%{"name" => "Other"})

      {:ok, _} = Errors.record_event(project, SentryEvent.parse(%{"message" => "one"}))

      {:ok, _} =
        Errors.record_event(
          project,
          SentryEvent.parse(%{"exception" => %{"values" => [%{"type" => "two"}]}})
        )

      {:ok, _} = Errors.record_event(other, SentryEvent.parse(%{"message" => "far away"}))

      mine = Errors.list_issues(project_id: project.id)
      assert length(mine) == 2

      one = Enum.find(mine, &(&1.title == "one"))
      {:ok, _} = Errors.update_issue_status(one, :resolved)

      assert length(Errors.list_issues(project_id: project.id, status: :unresolved)) == 1
      assert length(Errors.list_issues(project_id: project.id, status: :resolved)) == 1
    end

    test "search matches against title and culprit", %{project: project} do
      {:ok, _} =
        Errors.record_event(project, SentryEvent.parse(%{"message" => "database is on fire"}))

      {:ok, _} = Errors.record_event(project, SentryEvent.parse(%{"message" => "cache miss"}))

      assert [%Issue{title: "database is on fire"}] =
               Errors.list_issues(project_id: project.id, search: "database")
    end
  end

  describe "project keys" do
    test "create_project_key/2 mints a random public and secret key", %{project: project} do
      {:ok, %ProjectKey{public_key: pk, secret_key: sk}} = Errors.create_project_key(project.id)

      assert byte_size(pk) == 32
      assert byte_size(sk) == 32
      refute pk == sk
    end

    test "fetch_project_key_by_public_key/1 returns the key with its project", %{project: project} do
      {:ok, key} = Errors.create_project_key(project.id)
      assert {:ok, fetched} = Errors.fetch_project_key_by_public_key(key.public_key)
      assert fetched.project.id == project.id
    end
  end
end
