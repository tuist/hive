defmodule Hive.Specs.RevisionSummariesTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Specs
  alias Hive.Specs.RevisionSummaries

  defp user(email \\ "alice@example.com") do
    {:ok, user} =
      Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    user
  end

  defp two_revisions do
    user = user()

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "GitHub sign-in",
          "body" => "Keep source URL visible.\nImport comments."
        },
        user
      )

    {:ok, _spec} =
      Specs.update_spec(
        Specs.get_spec!(spec.id),
        %{
          "title" => "GitHub sign-in",
          "body" => "Keep source URL visible.\nImport discussion comments.\nSkip duplicates.",
          "lock_version" => spec.lock_version
        },
        user
      )

    spec = Specs.get_spec!(spec.id)
    {Enum.find(spec.revisions, &(&1.revision == 2)), spec}
  end

  test "summarize/2 invokes the agent with the previous and current revisions" do
    test_pid = self()
    {revision, _spec} = two_revisions()

    runner = fn input ->
      send(test_pid, {:summary_input, input})
      {:ok, %{summary: "Added a discussion import step and dedup behavior."}}
    end

    assert {:ok, updated} = RevisionSummaries.summarize(revision.id, runner: runner)
    assert updated.summary == "Added a discussion import step and dedup behavior."

    assert_receive {:summary_input, input}
    assert input.previous.body =~ "Import comments."
    assert input.current.body =~ "Import discussion comments."
    assert input.previous.title == "GitHub sign-in"
    assert input.previous.status == "draft"
  end

  test "summarize/2 accepts string-keyed agent output" do
    {revision, _spec} = two_revisions()
    runner = fn _input -> {:ok, %{"summary" => "Reworded the proposal."}} end

    assert {:ok, updated} = RevisionSummaries.summarize(revision.id, runner: runner)
    assert updated.summary == "Reworded the proposal."
  end

  test "summarize/2 skips when the LLM is unconfigured" do
    {revision, _spec} = two_revisions()
    runner = fn _input -> {:error, :llm_not_configured} end

    assert :skipped = RevisionSummaries.summarize(revision.id, runner: runner)

    refreshed = Hive.Repo.get!(Hive.Specs.Revision, revision.id)
    assert refreshed.summary == nil
  end

  test "summarize/2 skips the first revision" do
    user = user()

    {:ok, spec} = Specs.create_spec(%{"title" => "Spec", "body" => "Initial body text."}, user)
    spec = Specs.get_spec!(spec.id)
    [first] = spec.revisions

    refute_called = fn _input ->
      flunk("runner should not be called for the first revision")
    end

    assert :skipped = RevisionSummaries.summarize(first.id, runner: refute_called)
  end

  test "summarize/2 surfaces unexpected agent failures" do
    {revision, _spec} = two_revisions()
    runner = fn _input -> {:error, :boom} end

    assert {:error, :boom} = RevisionSummaries.summarize(revision.id, runner: runner)
  end
end
