defmodule Hive.Slack.UnfurlerTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Domains
  alias Hive.Drops
  alias Hive.Drops.WeeklyDigest
  alias Hive.Errors
  alias Hive.ErrorsHelpers
  alias Hive.Errors.SentryEvent
  alias Hive.Forage
  alias Hive.Forage.FeatureRequest
  alias Hive.Projects
  alias Hive.Postmortems
  alias Hive.Slack.Unfurler
  alias Hive.Specs

  @static_dashboard_paths [
    "/",
    "/ops",
    "/audit",
    "/forage",
    "/forage/new",
    "/forage/feature-requests/new",
    "/forage/feature-requests",
    "/forage/bug-reports",
    "/forage/feedback",
    "/forage/github-issues",
    "/forage/grafana-alerts",
    "/specs",
    "/specs/new",
    "/postmortems",
    "/drops",
    "/drops/subscribe",
    "/drops/digest",
    "/flights",
    "/domains",
    "/errors",
    "/projects",
    "/account/identities",
    "/account/notifications",
    "/ops/slack",
    "/ops/drops",
    "/ops/forage",
    "/ops/errors",
    "/ops/inference",
    "/ops/inference/profiles",
    "/ops/inference/providers",
    "/ops/audit"
  ]

  setup :verify_on_exit!

  defp app_url(path), do: HiveWeb.Endpoint.url() <> path
  defp unique_name(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp user! do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "alice-#{suffix}@example.com",
        provider: "test",
        provider_uid: "alice-#{suffix}@example.com"
      })

    user
  end

  defp spec!(attrs \\ %{}) do
    attrs = Map.put_new_lazy(attrs, "project_id", fn -> create_project!().id end)

    {:ok, spec} =
      Specs.create_spec(
        Map.merge(
          %{
            "title" => "Slack unfurling",
            "body" => "Hive should unfurl links.",
            "summary" => "Render Hive links inline."
          },
          attrs
        ),
        user!()
      )

    spec
  end

  defp create_project!(attrs \\ %{}) do
    {:ok, project} =
      Projects.create_project(
        Map.merge(%{name: "Project #{System.unique_integer([:positive])}"}, attrs)
      )

    project
  end

  defp create_domain!(attrs) do
    {:ok, domain} =
      attrs
      |> Map.put_new(:project_id, create_project!().id)
      |> Domains.create_domain()

    domain
  end

  defp insert_drop!(domain, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          source_type: :github_release,
          external_id: "tuist/hive@slack-#{System.unique_integer([:positive])}",
          title: "Route-owned Slack previews",
          body: "Every Hive dashboard route can now build a safe preview.",
          url: "https://github.com/tuist/hive/releases",
          version: "v1.0.0",
          published_at: ~U[2026-07-23 09:30:00Z]
        },
        attrs
      )

    {:ok, drop} = Drops.upsert_drop(attrs)
    Drops.replace_drop_domains(drop, [domain.id])
    drop
  end

  defp block_texts(%{"blocks" => blocks}) do
    Enum.flat_map(blocks, fn block ->
      [
        get_in(block, ["text", "text"])
        | block
          |> Map.get("fields", [])
          |> Enum.map(& &1["text"])
      ] ++
        (block
         |> Map.get("elements", [])
         |> Enum.flat_map(fn
           %{"text" => %{"text" => text}} -> [text]
           %{"text" => text} when is_binary(text) -> [text]
           _element -> []
         end))
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp button_url(%{"blocks" => blocks}) do
    blocks
    |> Enum.flat_map(&Map.get(&1, "elements", []))
    |> Enum.find(&(&1["type"] == "button"))
    |> Map.fetch!("url")
  end

  test "skips URLs whose host doesn't match the configured endpoint" do
    assert Unfurler.unfurl("https://example.org/specs/1") == :skip
  end

  test "skips malformed URLs" do
    assert Unfurler.unfurl("not a url") == :skip
    assert Unfurler.unfurl("") == :skip
  end

  test "skips Hive-hosted URLs that no dashboard route handles" do
    assert Unfurler.unfurl(app_url("/account/slack")) == :skip
  end

  test "every dashboard LiveView owns an unfurl strategy" do
    missing_modules =
      HiveWeb.Router.__routes__()
      |> Enum.flat_map(fn
        %{metadata: %{log_module: module}} -> [module]
        _route -> []
      end)
      |> Enum.uniq()
      |> Enum.reject(fn module ->
        Code.ensure_loaded!(module)

        function_exported?(module, :slack_unfurl, 2) or
          function_exported?(module, :open_graph, 0)
      end)

    assert missing_modules == []
  end

  test "unfurls every static dashboard route" do
    Enum.each(@static_dashboard_paths, fn path ->
      assert {:ok, payload} = Unfurler.unfurl(app_url(path))
      assert button_url(payload) == app_url(path)
    end)
  end

  test "uses generic metadata for private dashboard routes" do
    paths = [
      "/flights/#{Ecto.UUID.generate()}",
      "/ops/inference/profiles/#{Ecto.UUID.generate()}",
      "/ops/inference/tokens/#{Ecto.UUID.generate()}"
    ]

    Enum.each(paths, fn path ->
      assert {:ok, payload} = Unfurler.unfurl(app_url(path))
      assert button_url(payload) == app_url(path)
    end)

    assert {:ok, payload} = Unfurler.unfurl(app_url(List.first(paths)))
    assert block_texts(payload) |> Enum.any?(&(&1 =~ "Hive Flight"))
  end

  test "delegates spec detail links to the owning route" do
    spec = spec!()
    assert {:ok, payload} = Unfurler.unfurl(app_url("/specs/#{spec.number}"))

    assert block_texts(payload) |> Enum.any?(&(&1 == "Slack unfurling"))
    assert block_texts(payload) |> Enum.any?(&(&1 == "Render Hive links inline."))
    assert block_texts(payload) |> Enum.any?(&(&1 =~ "Spec ##{spec.number}"))
    assert button_url(payload) == app_url("/specs/#{spec.number}")

    assert {:ok, edit_payload} = Unfurler.unfurl(app_url("/specs/#{spec.number}/edit"))
    assert block_texts(edit_payload) |> Enum.any?(&(&1 == "Edit Slack unfurling"))
    assert button_url(edit_payload) == app_url("/specs/#{spec.number}/edit")
  end

  test "delegates postmortem detail links and skips missing postmortems" do
    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Delivery delay\n\nA worker backlog delayed notifications."},
        user!()
      )

    assert {:ok, payload} = Unfurler.unfurl(app_url("/postmortems/#{postmortem.number}"))
    assert block_texts(payload) |> Enum.any?(&(&1 == "Delivery delay"))
    assert button_url(payload) == app_url("/postmortems/#{postmortem.number}")

    {:ok, private_postmortem} =
      Postmortems.publish_postmortem(
        %{
          "body" => "# Private delivery delay\n\nAn internal backlog delayed notifications.",
          "visibility" => "private"
        },
        user!()
      )

    assert Unfurler.unfurl(app_url("/postmortems/#{private_postmortem.number}")) == :skip
    assert Unfurler.unfurl(app_url("/postmortems/99999999")) == :skip
  end

  test "skips specs with a private visibility override" do
    spec = spec!(%{"visibility_override" => "private"})

    assert Unfurler.unfurl(app_url("/specs/#{spec.number}")) == :skip
  end

  test "skips specs that inherit private project visibility" do
    {:ok, project} =
      Projects.create_project(%{
        name: "Private project #{System.unique_integer([:positive])}",
        visibility: :private
      })

    spec = spec!(%{"project_id" => project.id, "visibility" => "public"})

    assert Unfurler.unfurl(app_url("/specs/#{spec.number}")) == :skip
  end

  test "skips specs that do not exist" do
    assert Unfurler.unfurl(app_url("/specs/9999999")) == :skip
  end

  test "delegates domain detail links to the owning route" do
    domain =
      create_domain!(%{
        name: unique_name("Forage"),
        description: "Idea harvest.",
        visibility: :public
      })

    assert {:ok, payload} = Unfurler.unfurl(app_url("/domains/#{domain.id}"))

    assert block_texts(payload) |> Enum.any?(&(&1 == domain.name))
    assert block_texts(payload) |> Enum.any?(&(&1 == "Idea harvest."))
    assert block_texts(payload) |> Enum.any?(&(&1 =~ "Domain"))
    assert button_url(payload) == app_url("/domains/#{domain.id}")
  end

  test "skips private domains" do
    domain = create_domain!(%{name: unique_name("Secret"), visibility: :private})

    assert Unfurler.unfurl(app_url("/domains/#{domain.id}")) == :skip
  end

  test "delegates project detail links to the owning route" do
    project =
      create_project!(%{
        description: "Coordinates route-owned Slack previews.",
        visibility: :public
      })

    assert {:ok, payload} = Unfurler.unfurl(app_url("/projects/#{project.id}"))

    assert block_texts(payload) |> Enum.any?(&(&1 == project.name))

    assert block_texts(payload)
           |> Enum.any?(&(&1 == "Coordinates route-owned Slack previews."))

    assert button_url(payload) == app_url("/projects/#{project.id}")
  end

  test "skips private projects" do
    project = create_project!(%{visibility: :private})

    assert Unfurler.unfurl(app_url("/projects/#{project.id}")) == :skip
  end

  test "delegates forage detail links to the owning route" do
    {:ok, item} =
      Forage.create_feature_request(
        %{"title" => "Slack unfurling", "description" => "Render Hive links nicely."},
        user!()
      )

    assert {:ok, payload} = Unfurler.unfurl(app_url("/forage/items/manual/#{item.id}"))

    assert block_texts(payload) |> Enum.any?(&(&1 == "Slack unfurling"))
    assert block_texts(payload) |> Enum.any?(&(&1 =~ "Feature request"))
    assert button_url(payload) == app_url("/forage/items/manual/#{item.id}")
  end

  test "skips forage items that anonymous visitors cannot see" do
    {:ok, item} =
      Repo.insert(%FeatureRequest{
        type: :feature_request,
        title: "Internal idea",
        description: "Internal only.",
        status: :open,
        visibility: :organization,
        user_id: user!().id
      })

    assert Unfurler.unfurl(app_url("/forage/items/manual/#{item.id}")) == :skip
  end

  test "delegates drop detail links to the owning route" do
    domain = create_domain!(%{name: unique_name("Hive"), visibility: :public})
    drop = insert_drop!(domain)

    assert {:ok, payload} = Unfurler.unfurl(app_url("/drops/#{drop.number}"))
    assert block_texts(payload) |> Enum.any?(&(&1 == "Route-owned Slack previews"))
    assert block_texts(payload) |> Enum.any?(&(&1 =~ "v1.0.0"))
    assert button_url(payload) == app_url("/drops/#{drop.number}")
  end

  test "skips drops that anonymous visitors cannot see" do
    domain = create_domain!(%{name: unique_name("Internal"), visibility: :private})
    drop = insert_drop!(domain)

    assert Unfurler.unfurl(app_url("/drops/#{drop.number}")) == :skip
  end

  test "unfurls a published weekly Drops digest" do
    digest = insert_drop_digest!()

    assert {:ok, payload} =
             Unfurler.unfurl(app_url("/drops/digest/#{Date.to_iso8601(digest.week_start)}"))

    assert block_texts(payload) |> Enum.any?(&(&1 == "The connected week"))
    assert block_texts(payload) |> Enum.any?(&(&1 == "The week told one story."))
    assert button_url(payload) == app_url("/drops/digest/2026-07-06")
  end

  test "skips a missing historical weekly Drops digest" do
    assert Unfurler.unfurl(app_url("/drops/digest/2025-01-06")) == :skip
  end

  test "delegates error issue links to the owning route" do
    project = create_project!(%{name: unique_name("Errors")})
    {:ok, issue} = ErrorsHelpers.seed_issue(project, fake_sentry_event())

    assert {:ok, payload} = Unfurler.unfurl(app_url("/errors/#{issue.id}"))

    texts = block_texts(payload)

    assert Enum.any?(texts, &(&1 == "❗ #{issue.title}"))
    assert Enum.any?(texts, &(&1 == "*Project*\n#{project.name}"))
    assert Enum.any?(texts, &(&1 == "*Status*\nUnresolved"))
    assert Enum.any?(texts, &(&1 == "*Level*\nError"))
    assert Enum.any?(texts, &(&1 == "*Events*\n1"))
    assert Enum.any?(texts, &(&1 == "*Platform*\nElixir"))
    assert Enum.any?(texts, &(&1 =~ "Error issue / Hive"))
    assert Enum.any?(payload["blocks"], &(&1["type"] == "divider"))

    assert get_in(List.last(payload["blocks"]), ["elements", Access.at(0), "style"]) ==
             "primary"

    assert button_url(payload) == app_url("/errors/#{issue.id}")
  end

  test "delegates error event links with event-specific context" do
    project = create_project!(%{name: unique_name("Errors")})
    event_id = Ecto.UUID.generate() |> String.replace("-", "")
    {:ok, issue} = ErrorsHelpers.seed_issue(project, fake_sentry_event())

    stub(Errors, :fetch_event, fn issue_id, requested_event_id ->
      assert issue_id == issue.id
      assert requested_event_id == event_id

      %{
        event_id: event_id,
        timestamp: ~U[2026-09-05 08:30:00Z],
        level: "fatal",
        environment: "production",
        release: "2026.9.0",
        exception_type: "RuntimeError",
        exception_value: "checkout failed",
        top_frame_function: "Hive.Checkout.charge/1",
        top_frame_filename: "lib/hive/checkout.ex",
        payload: %{}
      }
    end)

    path = "/errors/#{issue.id}/events/#{event_id}"
    assert {:ok, payload} = Unfurler.unfurl(app_url(path))
    texts = block_texts(payload)

    assert Enum.any?(texts, &(&1 == "🚨 RuntimeError: checkout failed"))
    assert Enum.any?(texts, &(&1 == "Hive.Checkout.charge/1 at lib/hive/checkout.ex"))
    assert Enum.any?(texts, &(&1 == "*Event*\n#{String.slice(event_id, 0, 8)}"))
    assert Enum.any?(texts, &(&1 == "*Level*\nFatal"))
    assert Enum.any?(texts, &(&1 == "*Environment*\nproduction"))
    assert Enum.any?(texts, &(&1 == "*Release*\n2026.9.0"))
    assert Enum.any?(texts, &(&1 == "*Captured*\n2026-09-05 08:30:00 UTC"))
    assert Enum.any?(texts, &(&1 =~ "Error event / Hive"))
    assert button_url(payload) == app_url(path)
  end

  test "skips error issue links for issues that do not exist" do
    assert Unfurler.unfurl(app_url("/errors/#{Ecto.UUID.generate()}")) == :skip
  end

  test "skips error event links whose issue does not exist" do
    missing_issue = Ecto.UUID.generate()
    missing_event = Ecto.UUID.generate() |> String.replace("-", "")

    assert Unfurler.unfurl(app_url("/errors/#{missing_issue}/events/#{missing_event}")) == :skip
  end

  defp fake_sentry_event do
    %SentryEvent{
      event_id: Ecto.UUID.generate() |> String.replace("-", ""),
      timestamp: DateTime.utc_now(),
      level: "error",
      platform: "elixir",
      environment: "prod",
      release: nil,
      dist: nil,
      server_name: nil,
      transaction: nil,
      logger: nil,
      exception_type: "RuntimeError",
      exception_value: "kaboom",
      top_frame: nil,
      tags: %{},
      user: %{id: nil, email: nil, ip_address: nil},
      request: %{url: nil, method: nil},
      sdk_name: nil,
      sdk_version: nil,
      payload: %{}
    }
  end

  defp insert_drop_digest! do
    %WeeklyDigest{}
    |> WeeklyDigest.changeset(%{
      week_start: ~D[2026-07-06],
      week_end: ~D[2026-07-10],
      status: :published,
      title: "The connected week",
      summary: "The week told one story.",
      body: "Narrated body.",
      drop_ids: [Ecto.UUID.generate()],
      published_at: ~U[2026-07-10 17:00:00Z]
    })
    |> Repo.insert!()
  end
end
