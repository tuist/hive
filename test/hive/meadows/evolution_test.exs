defmodule Hive.Meadows.EvolutionTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Forage
  alias Hive.Meadows
  alias Hive.Meadows.Evolution
  alias Hive.Specs

  defp user(email \\ "alice@example.com") do
    {:ok, user} =
      Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    user
  end

  test "evolve_from_work_items/1 builds context and applies agent-proposed meadow changes" do
    test_pid = self()
    user = user()

    {:ok, tuist} =
      Meadows.create_meadow(%{
        name: "Tuist",
        description: "Developer infrastructure for build systems."
      })

    {:ok, _feature_request} =
      Forage.create_feature_request(
        %{
          "title" => "Show cache miss reasons",
          "description" =>
            "Expose why remote cache artifacts miss so teams can improve CI build times."
        },
        user
      )

    {:ok, _spec} =
      Specs.create_spec(
        %{
          "title" => "Build cache diagnostics",
          "summary" => "Explain build cache misses across CI and local developer workflows.",
          "body" => "Capture cache keys, affected build targets, and actionable remediation.",
          "meadow_ids" => [tuist.id]
        },
        user
      )

    runner = fn input ->
      send(test_pid, {:evolution_input, input})

      {:ok,
       %{
         changes: [
           %{
             action: "update",
             meadow_id: tuist.id,
             name: "Tuist Developer Tools",
             description:
               "Developer infrastructure for build systems, automation, and productive workflows.",
             rationale: "The existing meadow is broader than its description."
           },
           %{
             action: "create",
             name: "Build Cache",
             description:
               "Remote caching, cache diagnostics, and CI acceleration for development teams.",
             rationale: "Several signals point to cache observability as a durable domain."
           }
         ]
       }}
    end

    assert {:ok, %{created: [created], updated: [updated], skipped: []}} =
             Meadows.evolve_from_work_items(runner: runner)

    assert created.name == "Build Cache"
    assert updated.name == "Tuist Developer Tools"
    assert Repo.preload(created, :project).project.name == "Tuist"

    assert_receive {:evolution_input, input}
    assert Enum.any?(input.current_meadows, &(&1.name == "Tuist"))
    assert Enum.any?(input.work_items, &(&1.kind == "feature_request"))
    assert Enum.any?(input.work_items, &(&1.kind == "spec"))
  end

  test "apply_plan/1 skips too generic and too specific meadow suggestions" do
    assert {:ok, %{created: [created], skipped: skipped}} =
             Evolution.apply_plan(%{
               changes: [
                 %{
                   action: "create",
                   name: "Platform",
                   description: "Platform work for developer tools and app workflows.",
                   rationale: "Too broad."
                 },
                 %{
                   action: "create",
                   name: "Issue #7421 cache key",
                   description: "Build cache investigation for one GitHub issue.",
                   rationale: "Too narrow."
                 },
                 %{
                   action: "create",
                   name: "Developer Experience",
                   description:
                     "Developer onboarding, documentation, and CLI workflows for Tuist users.",
                   rationale: "A durable Tuist business domain."
                 }
               ]
             })

    assert created.name == "Developer Experience"
    assert Enum.map(skipped, & &1.reason) == [:unfit_meadow_name, :unfit_meadow_name]
  end

  test "apply_plan/1 skips suggestions outside Tuist business domains" do
    assert {:ok, %{created: [], skipped: [%{reason: :outside_tuist_business_domain}]}} =
             Evolution.apply_plan(%{
               changes: [
                 %{
                   action: "create",
                   name: "Billing",
                   description: "Invoices, payments, and subscriptions for customers.",
                   rationale: "This is not grounded in Tuist product signals."
                 }
               ]
             })
  end
end
