defmodule Hive.Specs.RevisionSummarySweeperTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Accounts
  alias Hive.Specs
  alias Hive.Specs.Revision
  alias Hive.Specs.RevisionSummarySweeper
  alias Hive.Specs.RevisionSummaryWorker

  defp user(email \\ "alice@example.com") do
    {:ok, user} =
      Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    user
  end

  defp updated_spec(attrs \\ %{}) do
    user = user()

    {:ok, spec} =
      Specs.create_spec(
        %{"title" => "GitHub sign-in", "body" => "Keep source URL visible."},
        user
      )

    {:ok, spec} =
      Specs.update_spec(
        Specs.get_spec!(spec.id),
        Map.merge(
          %{
            "title" => "GitHub sign-in",
            "body" => "Keep source URL visible.\nImport discussion comments.",
            "lock_version" => spec.lock_version
          },
          attrs
        ),
        user
      )

    Specs.get_spec!(spec.id)
  end

  test "perform/1 enqueues one summary worker per missing revision after the first draft" do
    stub(Hive.Agents, :enabled?, fn -> Process.get(:agents_enabled?, false) end)

    missing = updated_spec()
    complete = updated_spec(%{"title" => "GitHub OAuth"})

    complete_revision = Enum.find(complete.revisions, &(&1.revision == 2))

    complete_revision
    |> Revision.summary_changeset("Added OAuth-specific discussion import details.")
    |> Repo.update!()

    Process.put(:agents_enabled?, true)

    assert :ok = perform_job(RevisionSummarySweeper, %{})

    missing_revision_id = missing.revisions |> Enum.find(&(&1.revision == 2)) |> Map.fetch!(:id)

    assert [%Oban.Job{args: %{"revision_id" => ^missing_revision_id}}] =
             all_enqueued(worker: RevisionSummaryWorker)
  end

  test "perform/1 ignores initial drafts when no later revision needs a summary" do
    stub(Hive.Agents, :enabled?, fn -> Process.get(:agents_enabled?, false) end)

    _spec = updated_spec()

    Revision
    |> where([revision], revision.revision > 1)
    |> Repo.update_all(set: [summary: "Already summarized."])

    Process.put(:agents_enabled?, true)

    assert :ok = perform_job(RevisionSummarySweeper, %{})
    assert [] = all_enqueued(worker: RevisionSummaryWorker)
  end
end
