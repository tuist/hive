defmodule Hive.Specs.ReviewRequestsTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Specs
  alias Hive.Specs.ReviewRequests

  defp user(email, attrs \\ %{}) do
    {:ok, user} =
      Accounts.upsert_from_auth(
        Map.merge(
          %{email: email, provider: "test", provider_uid: email},
          attrs
        )
      )

    user
  end

  test "draft/3 invokes the agent with the latest revision and commenters" do
    requester = user("alice@example.com", %{name: "Alice"})
    reviewer = user("bob@example.com", %{name: "Bob"})

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "GitHub sign-in",
          "body" => "Initial proposal.",
          "summary" => "Let users sign in through GitHub."
        },
        requester
      )

    {:ok, _comment} = Specs.add_comment(spec, %{"body" => "Check token expiry."}, reviewer)

    {:ok, _spec} =
      Specs.update_spec(
        Specs.get_spec!(spec.id),
        %{"body" => "Initial proposal.\n\nRefresh tokens before they expire."},
        requester
      )

    spec = Specs.get_spec!(spec.id)
    test_pid = self()

    runner = fn input ->
      send(test_pid, {:review_request_input, input})

      {:ok,
       %{
         summary: "The latest revision clarifies token refresh behavior.",
         review_focus: ["Check the token expiry path.", "Confirm the acceptance criteria."]
       }}
    end

    assert {:ok, payload} =
             ReviewRequests.draft(spec, requester,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert payload.summary == "The latest revision clarifies token refresh behavior."

    assert payload.review_focus == [
             "Check the token expiry path.",
             "Confirm the acceptance criteria."
           ]

    assert Enum.map(payload.reviewers, & &1.email) == ["bob@example.com"]
    assert payload.last_revision.revision == 2

    assert_receive {:review_request_input, input}
    assert input.spec.title == "GitHub sign-in"
    assert input.spec.body =~ "Refresh tokens"
    assert input.last_revision.revision == 2
    refute Map.has_key?(input.last_revision, :body)
    assert input.requester.email == "alice@example.com"
    assert input.commenters == [%{email: "bob@example.com", name: "Bob"}]
  end

  test "draft/3 falls back when agents are disabled" do
    requester = user("alice@example.com")

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "GitHub sign-in",
          "body" => "Initial proposal.",
          "summary" => "Let users sign in through GitHub."
        },
        requester
      )

    assert {:ok, payload} = ReviewRequests.draft(Specs.get_spec!(spec.id), requester)
    assert payload.summary == "Let users sign in through GitHub."

    assert payload.review_focus == [
             "Review the current proposal, tradeoffs, and acceptance criteria."
           ]
  end
end
