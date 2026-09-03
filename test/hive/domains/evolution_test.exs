defmodule Hive.Domains.EvolutionTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Forage
  alias Hive.Domains
  alias Hive.Domains.Agents.EvolutionAgent
  alias Hive.Domains.Evolution
  alias Hive.Domains.EvolutionEvaluation
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
             project_ids: [project.id],
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
    refute Map.has_key?(input, :current_projects)
    assert Enum.any?(input.current_domains, &(&1.name == "Tuist"))
    assert Enum.any?(input.work_items, &(&1.kind == "feature_request"))
    assert Enum.any?(input.work_items, &(&1.kind == "spec"))
  end

  test "evolution operation schema no longer declares current_projects" do
    schema =
      EvolutionAgent.__operations__()
      |> Map.fetch!(:evolve_domains)
      |> Map.fetch!(:input_schema)

    refute Map.has_key?(schema.properties, :current_projects)
    refute "current_projects" in schema.required
  end

  test "evolve_from_work_items/1 truncates work-item bodies and domain descriptions" do
    test_pid = self()
    user = user()

    long_description = String.duplicate("d", 400)
    long_body = String.duplicate("w", 2_000)

    {:ok, project} = Projects.create_project(%{name: "Long", visibility: "public"})

    {:ok, _domain} =
      Domains.create_domain(%{
        name: "Long domain",
        description: long_description,
        project_id: project.id
      })

    {:ok, _feature_request} =
      Forage.create_feature_request(
        %{"title" => "Long title", "description" => long_body},
        user
      )

    runner = fn input ->
      send(test_pid, {:evolution_input, input})
      {:ok, %{changes: []}}
    end

    assert {:ok, _} = Domains.evolve_from_work_items(runner: runner)
    assert_receive {:evolution_input, input}

    long_item = Enum.find(input.work_items, &(&1.title == "Long title"))
    assert long_item
    assert String.length(long_item.body) == 603
    assert String.ends_with?(long_item.body, "...")

    long_domain = Enum.find(input.current_domains, &(&1.name == "Long domain"))
    assert long_domain
    assert String.length(long_domain.description) == 203
    assert String.ends_with?(long_domain.description, "...")
  end

  test "evolve_from_work_items/1 truncates a multibyte body without corrupting characters" do
    test_pid = self()
    user = user()
    multibyte = String.duplicate("🎉", 700)

    {:ok, _feature_request} =
      Forage.create_feature_request(
        %{"title" => "party", "description" => multibyte},
        user
      )

    runner = fn input ->
      send(test_pid, {:evolution_input, input})
      {:ok, %{changes: []}}
    end

    assert {:ok, _} = Domains.evolve_from_work_items(runner: runner)
    assert_receive {:evolution_input, input}

    item = Enum.find(input.work_items, &(&1.title == "party"))
    body = item.body

    assert String.valid?(body)
    assert String.length(body) == 603

    assert body
           |> String.replace_suffix("...", "")
           |> String.graphemes()
           |> Enum.all?(&(&1 == "🎉"))
  end

  test "evolve_from_work_items/1 persists no-op inputs and only reevaluates changed evidence" do
    test_pid = self()
    user = user()

    {:ok, _feature_request} =
      Forage.create_feature_request(
        %{
          "title" => "Explain cache misses",
          "description" => "Show developers why an artifact missed the remote cache."
        },
        user
      )

    runner = fn input ->
      send(test_pid, {:evolution_evaluated, Enum.map(input.work_items, & &1.id)})
      {:ok, %{changes: []}}
    end

    assert {:ok, %{created: [], updated: [], skipped: []}} =
             Domains.evolve_from_work_items(runner: runner)

    assert {:ok, %{created: [], updated: [], skipped: []}} =
             Domains.evolve_from_work_items(runner: runner)

    assert_receive {:evolution_evaluated, first_ids}
    refute_receive {:evolution_evaluated, _ids}
    assert Repo.aggregate(EvolutionEvaluation, :count) == 1

    {:ok, second_feature_request} =
      Forage.create_feature_request(
        %{
          "title" => "Compare cache keys",
          "description" => "Make divergent cache inputs visible across machines."
        },
        user
      )

    assert {:ok, %{created: [], updated: [], skipped: []}} =
             Domains.evolve_from_work_items(runner: runner)

    assert_receive {:evolution_evaluated, second_ids}
    assert second_feature_request.id in second_ids
    assert first_ids != second_ids
    assert Repo.aggregate(EvolutionEvaluation, :count) == 2
  end

  test "apply_plan/1 links new domains to the requested project" do
    {:ok, project} = Projects.create_project(%{name: "Atlas", visibility: "public"})

    assert {:ok, %{created: [created], skipped: []}} =
             Evolution.apply_plan(%{
               changes: [
                 %{
                   action: "create",
                   name: "Developer Workflows",
                   description:
                     "Developer onboarding, documentation, and CLI workflows for Tuist users.",
                   project_ids: [project.id],
                   rationale: "The signal belongs to Atlas."
                 }
               ]
             })

    assert [%{id: project_id}] = Repo.preload(created, :projects).projects
    assert project_id == project.id
  end

  test "evolution agent schema does not require a domain id for create changes" do
    assert {:ok, operation} = EvolutionAgent.__operation__(:evolve_domains)

    assert %{
             properties: %{
               changes: %{
                 items: %{
                   oneOf: [
                     create_schema,
                     update_schema
                   ]
                 }
               }
             }
           } = operation.output_schema

    refute Map.has_key?(create_schema.properties, :domain_id)
    assert create_schema.required == ["action", "name", "description", "rationale"]

    assert Map.has_key?(update_schema.properties, :domain_id)
    assert "domain_id" in update_schema.required
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

  test "apply_plan/1 skips domain creation when no project context is available" do
    assert {:ok, %{created: [], skipped: [%{reason: :missing_project}]}} =
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
