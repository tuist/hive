defmodule Hive.Domains.EvolutionTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Forage
  alias Hive.Domains
  alias Hive.Domains.Evolution
  alias Hive.Projects
  alias Hive.Specs

  defp user(email \\ "alice@example.com") do
    {:ok, user} =
      Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    user
  end

  test "evolve_from_work_items/1 builds context and applies agent-proposed domain changes" do
    test_pid = self()
    user = user()
    {:ok, project} = Projects.create_project(%{name: "Tuist", visibility: "public"})

    {:ok, tuist} =
      Domains.create_domain(%{
        name: "Tuist",
        description: "Developer infrastructure for build systems.",
        project_id: project.id
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
          "domain_ids" => [tuist.id]
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
             domain_id: tuist.id,
             name: "Tuist Developer Tools",
             description:
               "Developer infrastructure for build systems, automation, and productive workflows.",
             rationale: "The existing domain is broader than its description."
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
             Domains.evolve_from_work_items(runner: runner)

    assert created.name == "Build Cache"
    assert updated.name == "Tuist Developer Tools"
    assert [project] = Repo.preload(created, :projects).projects
    assert project.name == "Tuist"

    assert_receive {:evolution_input, input}
    assert Enum.any?(input.current_domains, &(&1.name == "Tuist"))
    assert Enum.any?(input.work_items, &(&1.kind == "feature_request"))
    assert Enum.any?(input.work_items, &(&1.kind == "spec"))
  end

  test "apply_plan/1 skips too generic and too specific domain suggestions" do
    {:ok, _project} = Projects.create_project(%{name: "Tuist", visibility: "public"})

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
    assert Enum.map(skipped, & &1.reason) == [:unfit_domain_name, :unfit_domain_name]
  end

  test "apply_plan/1 skips domain creation when the Tuist project has not been created" do
    assert {:ok, %{created: [], skipped: [%{reason: :missing_tuist_project}]}} =
             Evolution.apply_plan(%{
               changes: [
                 %{
                   action: "create",
                   name: "Developer Experience",
                   description:
                     "Developer onboarding, documentation, and CLI workflows for Tuist users.",
                   rationale: "A durable Tuist business domain."
                 }
               ]
             })
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
