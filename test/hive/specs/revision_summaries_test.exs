defmodule Hive.Specs.RevisionSummariesTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Agents.Sessions
  alias Hive.Accounts
  alias Hive.Specs
  alias Hive.Specs.Agents.RevisionSummaryAgent
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
    assert input.body_diff =~ "- Import comments."
    assert input.body_diff =~ "+ Import discussion comments."
    assert input.body_diff =~ "+ Skip duplicates."
    assert input.previous.title == "GitHub sign-in"
    assert input.previous.status == "draft"
    refute Map.has_key?(input.previous, :body)
    refute Map.has_key?(input.current, :body)
  end

  test "summarize/2 accepts string-keyed agent output" do
    {revision, _spec} = two_revisions()
    runner = fn _input -> {:ok, %{"summary" => "Reworded the proposal."}} end

    assert {:ok, updated} = RevisionSummaries.summarize(revision.id, runner: runner)
    assert updated.summary == "Reworded the proposal."
  end

  test "summarize/2 makes one bounded freeform model request" do
    {revision, _spec} = two_revisions()

    expect(Sessions, :run, fn RevisionSummaryAgent, prompt, opts ->
      assert prompt =~ "Body diff:"
      assert prompt =~ "+ Import discussion comments."
      assert opts[:load_project_instructions] == false
      assert opts[:max_turns] == 1

      {:ok, "Added discussion import and deduplication details."}
    end)

    assert {:ok, updated} =
             RevisionSummaries.summarize(revision.id)

    assert updated.summary == "Added discussion import and deduplication details."
  end

  test "summarize/2 does not start a second model path after an error" do
    {revision, _spec} = two_revisions()
    runner = fn _input -> {:error, :no_result_submitted} end

    assert {:error, :no_result_submitted} =
             RevisionSummaries.summarize(revision.id, runner: runner)
  end

  test "summarize/2 broadcasts after storing the summary" do
    {revision, _spec} = two_revisions()
    runner = fn _input -> {:ok, %{summary: "Clarified the discussion import behavior."}} end

    :ok = Specs.subscribe_to_spec(revision.spec_id)

    assert {:ok, updated} = RevisionSummaries.summarize(revision.id, runner: runner)
    assert updated.summary == "Clarified the discussion import behavior."
    assert_receive {:revision_summary_updated, revision_id}
    assert revision_id == revision.id
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
