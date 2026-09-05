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
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)
    stub(Hive.Errors.Event.Buffer, :insert, fn row -> {:ok, row} end)
    stub(Hive.Errors.IssueCoalescer, :observe, fn _server,
                                                   _project,
                                                   _fingerprint,
                                                   _event,
                                                   _opts ->
      :ok
    end)

    {:ok, project} = Projects.create_project(%{"name" => "Widgets"})
    {:ok, project: project}
  end

  describe "record_event/2" do
    test "casts one ClickHouse row and one issue observation per event",
         %{project: project} do
      event = SentryEvent.parse(%{"message" => "widget went sideways"})
      test_pid = self()

      expect(Hive.Errors.Event.Buffer, :insert, fn row ->
        send(test_pid, {:ch_row, row})
        {:ok, row}
      end)

      expect(Hive.Errors.IssueCoalescer, :observe, fn _server,
                                                       ^project,
                                                       fingerprint,
                                                       ^event,
                                                       _opts ->
        send(test_pid, {:observation, fingerprint})
        :ok
      end)

      assert :ok = Errors.record_event(project, event)
      assert_received {:ch_row, %Hive.Errors.Event{}}
      assert_received {:observation, fingerprint} when byte_size(fingerprint) == 64
    end

    test "ClickHouse row references the deterministic issue id", %{project: project} do
      event = SentryEvent.parse(%{"message" => "boom"})
      test_pid = self()

      expect(Hive.Errors.Event.Buffer, :insert, fn row ->
        send(test_pid, {:ch_row, row})
        {:ok, row}
      end)

      assert :ok = Errors.record_event(project, event)
      assert_received {:ch_row, row}

      fingerprint = Hive.Errors.Fingerprint.compute(event)
      assert row.issue_id == Issue.deterministic_id(project.id, fingerprint)
    end

    test "different fingerprints produce distinct issue ids", %{project: project} do
      a = SentryEvent.parse(%{"exception" => %{"values" => [%{"type" => "A"}]}})
      b = SentryEvent.parse(%{"exception" => %{"values" => [%{"type" => "B"}]}})

      fp_a = Hive.Errors.Fingerprint.compute(a)
      fp_b = Hive.Errors.Fingerprint.compute(b)

      refute Issue.deterministic_id(project.id, fp_a) ==
               Issue.deterministic_id(project.id, fp_b)
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

      {:ok, one} =
        Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "one"}))

      {:ok, _} =
        Hive.ErrorsHelpers.seed_issue(
          project,
          SentryEvent.parse(%{"exception" => %{"values" => [%{"type" => "two"}]}})
        )

      {:ok, _} =
        Hive.ErrorsHelpers.seed_issue(other, SentryEvent.parse(%{"message" => "far away"}))

      mine = Errors.list_issues(project_id: project.id)
      assert length(mine) == 2

      {:ok, _} = Errors.update_issue_status(one, :resolved)

      assert length(Errors.list_issues(project_id: project.id, status: :unresolved)) == 1
      assert length(Errors.list_issues(project_id: project.id, status: :resolved)) == 1
    end

    test "search matches against title and culprit", %{project: project} do
      {:ok, _} =
        Hive.ErrorsHelpers.seed_issue(
          project,
          SentryEvent.parse(%{"message" => "database is on fire"})
        )

      {:ok, _} =
        Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "cache miss"}))

      assert [%Issue{title: "database is on fire"}] =
               Errors.list_issues(project_id: project.id, search: "database")
    end
  end

  describe "project keys" do
    test "create_project_key/2 mints a random public and secret key", %{project: project} do
      {:ok, %ProjectKey{public_key: pk, secret_key: sk, dsn_project_id: project_id}} =
        Errors.create_project_key(project.id)

      assert byte_size(pk) == 32
      assert byte_size(sk) == 32
      assert is_integer(project_id)
      refute pk == sk
    end

    test "renders a Data Source Name with a numeric project id", %{project: project} do
      {:ok, key} = Errors.create_project_key(project.id)

      assert ProjectKey.dsn(key, "https://errors.example.com") ==
               "https://#{key.public_key}@errors.example.com/#{key.dsn_project_id}"
    end

    test "fetch_project_key_by_public_key/1 returns the key with its project", %{project: project} do
      {:ok, key} = Errors.create_project_key(project.id)
      assert {:ok, fetched} = Errors.fetch_project_key_by_public_key(key.public_key)
      assert fetched.project.id == project.id
    end
  end
end
