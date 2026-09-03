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
    assert Enum.any?(input.current_projects, &(&1.id == project.id))
    assert Enum.any?(input.current_domains, &(&1.name == "Tuist"))
    assert Enum.any?(input.work_items, &(&1.kind == "feature_request"))
    assert Enum.any?(input.work_items, &(&1.kind == "spec"))
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

  test "evolve_from_work_items/1 records a failed evaluation and skips retries with unchanged input" do
    test_pid = self()
    user = user()

    {:ok, _feature_request} =
      Forage.create_feature_request(
        %{
          "title" => "Cache the cache",
          "description" => "Persist a memoized index of prior lookups."
        },
        user
      )

    error =
      ReqLLM.Error.API.Request.exception(
        reason: "Provider response error (502): The upstream provider request failed.",
        status: 502,
        response_body: "502",
        request_body: ""
      )

    runner = fn _input ->
      send(test_pid, :runner_called)
      {:error, error}
    end

    assert {:error, _} = Domains.evolve_from_work_items(runner: runner)
    assert_receive :runner_called

    assert %EvolutionEvaluation{outcome: :failed, reason: "llm_provider_unavailable"} =
             Repo.one!(EvolutionEvaluation)

    assert {:ok, %{created: [], updated: [], skipped: []}} =
             Domains.evolve_from_work_items(runner: runner)

    refute_receive :runner_called
  end

  test "evolve_from_work_items/1 re-evaluates a failed fingerprint once its cooldown passes" do
    test_pid = self()
    user = user()

    {:ok, _feature_request} =
      Forage.create_feature_request(
        %{
          "title" => "Delta ingestion",
          "description" => "Ship a per-domain change stream so evolution can see novelty."
        },
        user
      )

    error =
      ReqLLM.Error.API.Request.exception(
        reason: "Provider response error (502): The upstream provider request failed.",
        status: 502,
        response_body: "502",
        request_body: ""
      )

    runner = fn _input ->
      send(test_pid, :runner_called)
      {:error, error}
    end

    assert {:error, _} = Domains.evolve_from_work_items(runner: runner)
    assert_receive :runner_called

    evaluation = Repo.one!(EvolutionEvaluation)
    past = DateTime.utc_now() |> DateTime.add(-90_000, :second) |> DateTime.truncate(:second)

    Repo.update_all(
      from(evaluation in EvolutionEvaluation,
        where: evaluation.id == ^evaluation.id
      ),
      set: [evaluated_at: past]
    )

    success_runner = fn _input ->
      send(test_pid, :retry_runner_called)
      {:ok, %{changes: []}}
    end

    assert {:ok, %{created: [], updated: [], skipped: []}} =
             Domains.evolve_from_work_items(runner: success_runner)

    assert_receive :retry_runner_called

    assert %EvolutionEvaluation{outcome: :noop, reason: nil} =
             Repo.one!(EvolutionEvaluation)
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
