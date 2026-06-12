import Ecto.Query

alias Hive.Accounts
alias Hive.Accounts.UserIdentity
alias Hive.Forage
alias Hive.Forage.FeatureRequest
alias Hive.Forage.Grafana
alias Hive.Meadows
alias Hive.Meadows.GitHubRepository
alias Hive.Meadows.Meadow
alias Hive.Meadows.Webhook
alias Hive.Meadows.Webhooks
alias Hive.Repo
alias Hive.Specs
alias Hive.Specs.Comment
alias Hive.Specs.Revision
alias Hive.Specs.Spec

account_identities = [
  {"test@hive.dev", "google", "google-test-hive-dev"},
  {"maya@example.com", "google", "google-maya-example"},
  {"maya@example.com", "github", "github-maya-example"},
  {"octo@example.com", "github", "github-octo-example"},
  {"oidc@example.com", "oidc", "oidc-example"}
]

UserIdentity
|> where([identity], identity.provider in ["dev", "seed"])
|> where([identity], identity.provider_uid in ["dev", "test@hive.dev", "maya@example.com"])
|> Repo.delete_all()

Enum.each(account_identities, fn {email, provider, provider_uid} ->
  {:ok, _user} =
    Accounts.upsert_from_auth(%{
      email: email,
      provider: provider,
      provider_uid: provider_uid
    })
end)

feature_requests = [
  {
    "maya@example.com",
    %{
      "title" => "Import feature requests from GitHub Discussions",
      "description" =>
        "Let maintainers connect a GitHub Discussions category so public ideas can flow into Forage without copying them by hand."
    }
  },
  {
    "jon@example.com",
    %{
      "title" => "Group forage by source and priority",
      "description" =>
        "Show feature requests, bug reports, and alerts in one place while still making it easy to filter the list by source and urgency."
    }
  },
  {
    "priya@example.com",
    %{
      "title" => "Let users subscribe to feature request updates",
      "description" =>
        "Allow authenticated requesters to follow a feature request and receive updates when its status changes."
    }
  },
  {
    "sam@example.com",
    %{
      "title" => "Capture affected organization on public requests",
      "description" =>
        "When a signed-in user belongs to an organization, attach that organization to the request so the team can understand who is asking."
    }
  }
]

Enum.each(feature_requests, fn {email, attrs} ->
  exists? =
    FeatureRequest
    |> where([feature_request], feature_request.title == ^attrs["title"])
    |> Repo.exists?()

  unless exists? do
    user =
      Accounts.get_user_by_email(email) ||
        Accounts.upsert_from_auth(%{
          email: email,
          provider: "seed",
          provider_uid: email
        })
        |> then(fn {:ok, user} -> user end)

    {:ok, _feature_request} = Forage.create_feature_request(attrs, user)
  end
end)

meadows = [
  %{
    "name" => "Hive",
    "description" => "Agentic meadow orchestration for one organization.",
    "visibility" => "public",
    "github_repository_owner" => "tuist",
    "github_repository_name" => "hive"
  },
  %{
    "name" => "Tuist",
    "description" =>
      "Developer tools for generating, maintaining, and optimizing Xcode projects.",
    "visibility" => "public",
    "github_repository_owner" => "tuist",
    "github_repository_name" => "tuist"
  },
  %{
    "name" => "Noora",
    "description" => "Design system components shared across Tuist meadows.",
    "visibility" => "public",
    "github_repository_owner" => "tuist",
    "github_repository_name" => "tuist"
  },
  %{
    "name" => "Atlas",
    "description" => "A meadow boundary without a GitHub repository connected yet.",
    "visibility" => "private"
  }
]

Enum.each(meadows, fn attrs ->
  exists? =
    Meadow
    |> where([meadow], meadow.name == ^attrs["name"])
    |> Repo.exists?()

  unless exists? do
    {:ok, _meadow} = Meadows.create_meadow(attrs)
  end
end)

github_issue_fixtures = [
  {"tuist", "hive",
   [
     %{
       number: 101,
       title: "Surface forage source counts in the sidebar",
       body:
         "Show the number of open feature requests, bug reports, and GitHub issues per source so reviewers can scan workload without opening every page."
     },
     %{
       number: 102,
       title: "Allow specs to link multiple forage sources",
       body:
         "A single spec can be driven by both a feature request and a bug report. Today only one source can be attached. Capture all of them on the spec detail page."
     },
     %{
       number: 103,
       title: "Render GitHub issue body as Markdown",
       body:
         "Most issue bodies use Markdown for code blocks and lists. Render them as Markdown in the forage view so the excerpt is useful at a glance."
     },
     %{
       number: 104,
       title: "`Markdown.inline/1` should accept `Phoenix.HTML.safe` input",
       body:
         "Callers that already hold a `{:safe, iodata}` tuple have to unwrap it before passing to `Markdown.inline/1`. Accept both shapes so the function composes with `Phoenix.HTML.html_escape/1`."
     },
     %{
       number: 105,
       title: "Persist filter selection in the `?filters=` query string",
       body:
         "When a reviewer adds a filter like `state:closed` we should reflect it in the URL so the view is shareable and survives a refresh."
     }
   ]},
  {"tuist", "tuist",
   [
     %{
       number: 7421,
       title: "Improve cache hit rate for binary frameworks",
       body:
         "The remote cache misses for binary frameworks more often than it should. Investigate the cache key inputs to see whether build settings outside the project file are unintentionally part of the key."
     },
     %{
       number: 7422,
       title: "Document `tuist install` in the getting started guide",
       body:
         "Newcomers reach for `tuist install` before `tuist generate` once Swift Package dependencies are involved. The guide should mention it earlier."
     },
     %{
       number: 7423,
       title:
         "Static framework with `.metal` produces `default.metallib` that ignores Metal-related build settings",
       body: """
       ### What happened?

       When a static framework target contains `.metal` files, `tuist generate` emits a `default.metallib` resource that ignores the `MTL_*` build settings configured on the target. The resulting binary uses the default Metal compiler flags instead of the project-specific ones.

       ### Steps to reproduce

       1. Create a static framework with a `.metal` shader.
       2. Set `MTL_FAST_MATH = NO` on the target.
       3. Run `tuist generate` and inspect the generated `default.metallib`.
       """
     },
     %{
       number: 7424,
       title:
         "Crash in `Tuist.Generator` when `Project.swift` references a missing `Package.swift`",
       body: """
       ### What happened?

       Running `tuist generate` against a project whose `Project.swift` declares a Swift Package dependency that no longer exists on disk crashes with `MissingPackageManifest` instead of surfacing a helpful error.
       """
     },
     %{
       number: 7425,
       title: "Add `--quiet` flag to `tuist cache warm`",
       body:
         "CI logs are noisy. A `--quiet` flag that suppresses per-target progress lines and only prints the final summary would make cache-warm output easy to scan."
     }
   ]}
]

Enum.each(github_issue_fixtures, fn {owner, name, entries} ->
  case Repo.get_by(GitHubRepository, owner: owner, name: name) do
    nil ->
      :skip

    %GitHubRepository{} = repository ->
      Forage.reconcile_repository_github_issues(repository, entries)
  end
end)

specs = [
  %{
    author: "maya@example.com",
    source_title: "Import feature requests from GitHub Discussions",
    meadow_names: ["Hive"],
    attrs: %{
      "title" => "GitHub Discussions forage import",
      "summary" =>
        "Import public GitHub Discussions into Forage while preserving source metadata for reviewers.",
      "body" => """
      Connect a GitHub Discussions category as a forage source so public meadow ideas flow into Hive without manual copying.

      The importer should preserve the original title, body, author signal, and source URL. Imported items should appear alongside manually submitted feature requests and keep enough metadata for reviewers to trace the idea back to GitHub.

      Acceptance criteria:
      - Maintainers can configure one GitHub Discussions category.
      - New discussions become feature request forage items.
      - Existing imported items are not duplicated when the importer runs again.
      """,
      "status" => "proposed"
    },
    comments: [
      {"jon@example.com",
       "This should keep the source URL visible on the forage item and the spec."},
      {"guest@example.com",
       "It would help if imported items linked back to the discussion comments too."}
    ]
  },
  %{
    author: "jon@example.com",
    source_title: "Group forage by source and priority",
    meadow_names: ["Hive", "Noora"],
    attrs: %{
      "title" => "Forage source and priority grouping",
      "summary" =>
        "Group incoming forage by source and urgency without making every alert become a spec.",
      "visibility" => "private",
      "body" => """
      Add lightweight grouping to Forage so reviewers can scan incoming work by source and urgency without losing the current source-specific pages.

      The first version should keep the sidebar simple and make prioritization visible in the list rows. Alerts can remain operational forage that does not require a spec unless a member explicitly promotes one.

      Acceptance criteria:
      - Forage rows show their source and priority.
      - The feature request page keeps its existing stats.
      - Grafana alerts can stay outside the spec workflow by default.
      """,
      "status" => "draft"
    },
    comments: [
      {"priya@example.com",
       "The alert exception is important. Not every signal should become meadow planning."}
    ]
  },
  %{
    author: "priya@example.com",
    source_title: "Let users subscribe to feature request updates",
    meadow_names: ["Hive"],
    attrs: %{
      "title" => "Feature request subscriptions",
      "summary" =>
        "Let authenticated requesters subscribe to feature request updates and follow converted specs.",
      "body" => """
      Let authenticated requesters subscribe to updates on feature requests they care about.

      The subscription should notify people when a request is planned, closed, or converted into a spec. This gives contributors a clear feedback loop without exposing private implementation work.

      Acceptance criteria:
      - Signed-in users can subscribe and unsubscribe.
      - Status changes notify subscribers.
      - Converting a request into a spec includes a link to the spec.
      """,
      "status" => "approved"
    },
    comments: [
      {"maya@example.com", "Let's make sure the email copy links to the public spec page."},
      {"sam@example.com", "Could this also support digest mode later?"}
    ]
  },
  %{
    author: "maya@example.com",
    meadow_names: ["Hive"],
    attrs: %{
      "title" => "Spec activity feed",
      "summary" =>
        "Stream spec status, revision, and comment events so members can follow proposals without polling.",
      "body" => """
      # Why

      Members ask "what changed on the memory spec this week?" and end up scrolling the revision table looking for status flips. We need a denser surface that ties together revisions, comments, and status changes in one chronological view.

      ## Goals

      1. One feed per spec that lists every revision, comment, and status change in order.
      2. A workspace-wide feed at `/activity` that aggregates events across all visible specs.
      3. PubSub fan-out so any subscriber (LiveView, MCP) sees the same event stream.
      4. Markdown previews for comments inline, without a full re-render.

      ## Non-goals

      - Email or Slack delivery (separate spec).
      - Per-user mute/follow controls in v1.
      - Replacing the revision table on the spec page.

      ## Event shape

      Every activity row is a typed event with a stable JSON shape, persisted to `spec_events`:

      ```elixir
      defmodule Hive.Specs.Event do
        use Ecto.Schema

        @primary_key {:id, :binary_id, autogenerate: true}
        @foreign_key_type :binary_id

        schema "spec_events" do
          field :kind, Ecto.Enum, values: [:revision, :comment, :status_changed]
          field :payload, :map
          belongs_to :spec, Hive.Specs.Spec
          belongs_to :actor, Hive.Accounts.User
          timestamps(type: :utc_datetime, updated_at: false)
        end
      end
      ```

      Status-change payloads carry the transition:

      ```json
      {
        "from": "proposed",
        "to": "approved",
        "lock_version": 4
      }
      ```

      ## Subscriptions

      LiveView subscribes per spec with `Phoenix.PubSub.subscribe(Hive.PubSub, "spec:" <> spec_id)`. The workspace feed subscribes to `"specs:activity"`. Both topics are emitted by the same publisher:

      ```elixir
      def publish(%Event{spec_id: spec_id} = event) do
        Phoenix.PubSub.broadcast(Hive.PubSub, "spec:" <> spec_id, {:spec_event, event})
        Phoenix.PubSub.broadcast(Hive.PubSub, "specs:activity", {:spec_event, event})
      end
      ```

      ## Acceptance criteria

      - [ ] Every `update_spec/3` and `add_comment/3` writes a typed `Hive.Specs.Event`.
      - [ ] `/specs/:n` shows the per-spec feed live without polling.
      - [ ] `/activity` shows the workspace feed and respects visibility.
      - [ ] MCP `list_events` tool returns the same events for connected agents.

      ## Open questions

      | Question | Owner | Status |
      | --- | --- | --- |
      | Retention policy for events | maya | open |
      | Whether comments mirror to events or live in their own table | jon | leaning toward events table |
      | How to backfill events for existing specs | priya | needs design |

      > [!IMPORTANT]
      > **Why paused?** We want the [forage GitHub issues sync](/specs/4) to land first so the event publisher has a real second producer to design against. Resume once that is shipped.

      > [!TIP]
      > Subscribing to `"specs:activity"` from a LiveView keeps the workspace feed real-time without polling.
      """,
      "status" => "paused"
    },
    comments: [
      {"jon@example.com",
       "Agree on pausing. Let's revisit once we have two producers (specs + forage) feeding the publisher."},
      {"priya@example.com",
       "The `spec_events` table is fine as a starting point but I want to look at partitioning before we go to prod."}
    ]
  },
  %{
    author: "sam@example.com",
    meadow_names: ["Hive"],
    attrs: %{
      "title" => "Auto-generate specs from forage with an LLM",
      "summary" =>
        "Convert feature requests into draft specs automatically using an LLM that fills in the proposal template.",
      "body" => """
      # Proposal

      When a feature request is marked `planned`, trigger an LLM to draft a spec body from the request title and description, plus relevant context from the linked meadow. The draft is saved as a `draft` spec for a human to refine.

      ## Sketch

      ```elixir
      def draft_spec_from_request(%FeatureRequest{} = request) do
        prompt = build_prompt(request)
        {:ok, body} = LLM.complete(prompt, model: "claude-opus-4-8")
        Specs.create_spec(%{"title" => request.title, "body" => body, "status" => "draft"}, system_user())
      end
      ```

      ## Why rejected

      > [!CAUTION]
      > We don't have a clear quality signal that the generated drafts would be worth more than the noise they add to the spec list.

      Concretely:

      - No baseline for what "good" looks like — every feature request is different.
      - The current spec workflow assumes humans wrote the body, so the revision history would be polluted with LLM regenerations.
      - We don't have an LLM client wired into Hive yet; building one for this use case is premature.

      Revisit once we ship the [activity feed](/specs/5) and have a clearer picture of what good spec hygiene looks like in practice. A *retrieval-only* path (LLM summarizes existing specs, doesn't draft new ones) is a more promising direction.
      """,
      "status" => "rejected"
    },
    comments: [
      {"maya@example.com",
       "Right call to reject this. The summarization angle is interesting though — I'd open a fresh spec for it rather than reopening this one."}
    ]
  },
  %{
    author: "sam@example.com",
    meadow_names: ["Hive", "Tuist"],
    attrs: %{
      "title" => "Spec revision workflow for MCP clients",
      "summary" =>
        "Support local spec editing through MCP with revision checks and stale update handling.",
      "body" => """
      Make specs comfortable to edit from local tools through MCP by exposing pull, edit, and push operations with revision checks.

      Clients should fetch the current revision before editing and include that revision when pushing changes back. If the spec changed meanwhile, Hive should reject the update with the latest revision so the client can pull first.

      Acceptance criteria:
      - MCP clients can list and fetch specs.
      - MCP updates require an expected revision.
      - Stale updates return the current revision and spec payload.
      """,
      "status" => "shipped"
    },
    comments: [
      {"maya@example.com", "This is ready to use as the canonical local-editing demo."}
    ]
  }
]

spec_needs_update? = fn spec, attrs ->
  spec = Repo.preload(spec, :meadows)
  meadow_ids = Map.get(attrs, "meadow_ids", [])

  spec.title != attrs["title"] or
    spec.body != attrs["body"] or
    spec.summary != attrs["summary"] or
    Atom.to_string(spec.status) != attrs["status"] or
    Atom.to_string(spec.visibility) != Map.get(attrs, "visibility", "public") or
    Enum.sort(Enum.map(spec.meadows, & &1.id)) != Enum.sort(meadow_ids)
end

Enum.each(specs, fn seed ->
  {:ok, user} =
    Accounts.upsert_from_auth(%{
      email: seed.author,
      provider: "seed",
      provider_uid: seed.author
    })

  attrs =
    case seed[:source_title] do
      nil ->
        seed.attrs

      source_title ->
        feature_request = Repo.get_by!(FeatureRequest, title: source_title)
        Map.put(seed.attrs, "source_feature_request_id", feature_request.id)
    end
    |> Map.put_new("visibility", "public")
    |> Map.put(
      "meadow_ids",
      seed
      |> Map.get(:meadow_names, [])
      |> Enum.map(fn name -> Repo.get_by!(Meadow, name: name).id end)
    )

  spec =
    case Repo.get_by(Spec, title: seed.attrs["title"]) do
      nil ->
        {:ok, spec} = Specs.create_spec(attrs, user)
        spec

      spec ->
        if spec_needs_update?.(spec, attrs) do
          {:ok, spec} = Specs.update_spec(spec, attrs, user)
          spec
        else
          spec
        end
    end

  revision_exists? =
    Revision
    |> where([revision], revision.spec_id == ^spec.id and revision.revision == ^spec.lock_version)
    |> Repo.exists?()

  unless revision_exists? do
    {:ok, _revision} =
      %Revision{}
      |> Revision.changeset(%{
        revision: spec.lock_version,
        title: spec.title,
        body: spec.body,
        status: spec.status,
        spec_id: spec.id,
        user_id: user.id
      })
      |> Repo.insert()
  end

  Enum.each(seed.comments, fn {author, body} ->
    comment_attrs =
      if String.contains?(author, "@") do
        %{"body" => body}
      else
        %{"author_name" => author, "body" => body}
      end

    comment_user =
      if String.contains?(author, "@") do
        {:ok, user} =
          Accounts.upsert_from_auth(%{
            email: author,
            provider: "seed",
            provider_uid: author
          })

        user
      end

    comment_exists? =
      Comment
      |> where([comment], comment.spec_id == ^spec.id and comment.body == ^body)
      |> Repo.exists?()

    unless comment_exists? do
      {:ok, _comment} = Specs.add_comment(spec, comment_attrs, comment_user)
    end
  end)
end)

meadow_webhooks = [
  %{meadow_name: "Hive", name: "Seed Grafana", source: :grafana},
  %{meadow_name: "Tuist", name: "Seed Grafana", source: :grafana}
]

Enum.each(meadow_webhooks, fn seed ->
  meadow = Repo.get_by!(Meadow, name: seed.meadow_name)

  exists? =
    Webhook
    |> where(
      [webhook],
      webhook.meadow_id == ^meadow.id and webhook.name == ^seed.name and
        webhook.source == ^seed.source
    )
    |> Repo.exists?()

  unless exists? do
    {:ok, {_webhook, token}} =
      Webhooks.create(meadow, %{
        "name" => seed.name,
        "source" => Atom.to_string(seed.source)
      })

    IO.puts(
      "Seeded webhook for #{seed.meadow_name} (#{seed.source}). Token (shown once): #{token}"
    )
  end
end)

grafana_alert_seeds = [
  %{
    meadow_name: "Hive",
    payload: %{
      "status" => "firing",
      "alerts" => [
        %{
          "status" => "firing",
          "fingerprint" => "seed-hive-latency",
          "labels" => %{
            "alertname" => "HighRequestLatency",
            "service" => "hive-web",
            "severity" => "critical"
          },
          "annotations" => %{
            "summary" => "Request latency over budget",
            "description" => "p95 latency on hive-web is 820ms, above the 500ms budget."
          },
          "startsAt" => "2026-06-10T17:32:00Z",
          "endsAt" => "0001-01-01T00:00:00Z",
          "generatorURL" => "https://grafana.example/alert/hive-latency"
        }
      ]
    }
  },
  %{
    meadow_name: "Hive",
    payload: %{
      "status" => "firing",
      "alerts" => [
        %{
          "status" => "firing",
          "fingerprint" => "seed-hive-errors",
          "labels" => %{
            "alertname" => "ErrorRateSpike",
            "service" => "hive-web",
            "severity" => "warning"
          },
          "annotations" => %{
            "summary" => "Error rate spike on hive-web",
            "description" => "5xx rate climbed to 2.1% over the last 5 minutes."
          },
          "startsAt" => "2026-06-10T17:45:00Z",
          "generatorURL" => "https://grafana.example/alert/hive-errors"
        }
      ]
    }
  },
  %{
    meadow_name: "Tuist",
    payload: %{
      "status" => "resolved",
      "alerts" => [
        %{
          "status" => "resolved",
          "fingerprint" => "seed-tuist-cache-hit",
          "labels" => %{
            "alertname" => "CacheHitRateLow",
            "service" => "tuist-cache",
            "severity" => "warning"
          },
          "annotations" => %{
            "summary" => "Cache hit rate recovered",
            "description" =>
              "Tuist cache hit rate is back above 80% after dipping to 62% for ~12 minutes."
          },
          "startsAt" => "2026-06-10T16:10:00Z",
          "endsAt" => "2026-06-10T16:22:00Z",
          "generatorURL" => "https://grafana.example/alert/tuist-cache"
        }
      ]
    }
  },
  %{
    meadow_name: "Tuist",
    payload: %{
      "status" => "firing",
      "alerts" => [
        %{
          "status" => "firing",
          "fingerprint" => "seed-tuist-queue",
          "labels" => %{
            "alertname" => "BuildQueueBacklog",
            "service" => "tuist-builds",
            "severity" => "critical"
          },
          "annotations" => %{
            "summary" => "Build queue backlog growing",
            "description" =>
              "Pending builds queue has grown to 142 jobs over the last 10 minutes."
          },
          "startsAt" => "2026-06-10T17:50:00Z",
          "generatorURL" => "https://grafana.example/alert/tuist-queue"
        }
      ]
    }
  }
]

Enum.each(grafana_alert_seeds, fn seed ->
  meadow = Repo.get_by!(Meadow, name: seed.meadow_name)

  webhook =
    Repo.one!(
      from webhook in Webhook,
        where: webhook.meadow_id == ^meadow.id and webhook.source == ^:grafana,
        limit: 1
    )

  {:ok, _alerts} = Grafana.ingest(meadow, webhook, seed.payload)
end)
