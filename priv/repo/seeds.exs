import Ecto.Query

alias Hive.Accounts
alias Hive.Accounts.UserIdentity
alias Hive.Forage
alias Hive.Forage.FeatureRequest
alias Hive.Forage.Grafana
alias Hive.Products
alias Hive.Products.GitHubRepository
alias Hive.Products.Product
alias Hive.Products.Webhook
alias Hive.Products.Webhooks
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

products = [
  %{
    "name" => "Hive",
    "description" => "Agentic product orchestration for one organization.",
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
    "description" => "Design system components shared across Tuist products.",
    "visibility" => "public",
    "github_repository_owner" => "tuist",
    "github_repository_name" => "tuist"
  },
  %{
    "name" => "Atlas",
    "description" => "A product boundary without a GitHub repository connected yet.",
    "visibility" => "private"
  }
]

Enum.each(products, fn attrs ->
  exists? =
    Product
    |> where([product], product.name == ^attrs["name"])
    |> Repo.exists?()

  unless exists? do
    {:ok, _product} = Products.create_product(attrs)
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
    product_names: ["Hive"],
    attrs: %{
      "title" => "GitHub Discussions forage import",
      "summary" =>
        "Import public GitHub Discussions into Forage while preserving source metadata for reviewers.",
      "body" => """
      Connect a GitHub Discussions category as a forage source so public product ideas flow into Hive without manual copying.

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
    product_names: ["Hive", "Noora"],
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
       "The alert exception is important. Not every signal should become product planning."}
    ]
  },
  %{
    author: "priya@example.com",
    source_title: "Let users subscribe to feature request updates",
    product_names: ["Hive"],
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
      "status" => "accepted"
    },
    comments: [
      {"maya@example.com", "Let's make sure the email copy links to the public spec page."},
      {"sam@example.com", "Could this also support digest mode later?"}
    ]
  },
  %{
    author: "sam@example.com",
    product_names: ["Hive", "Tuist"],
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
  spec = Repo.preload(spec, :products)
  product_ids = Map.get(attrs, "product_ids", [])

  spec.title != attrs["title"] or
    spec.body != attrs["body"] or
    spec.summary != attrs["summary"] or
    Atom.to_string(spec.status) != attrs["status"] or
    Atom.to_string(spec.visibility) != Map.get(attrs, "visibility", "public") or
    Enum.sort(Enum.map(spec.products, & &1.id)) != Enum.sort(product_ids)
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
      "product_ids",
      seed
      |> Map.get(:product_names, [])
      |> Enum.map(fn name -> Repo.get_by!(Product, name: name).id end)
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

product_webhooks = [
  %{product_name: "Hive", name: "Seed Grafana", source: :grafana},
  %{product_name: "Tuist", name: "Seed Grafana", source: :grafana}
]

Enum.each(product_webhooks, fn seed ->
  product = Repo.get_by!(Product, name: seed.product_name)

  exists? =
    Webhook
    |> where(
      [webhook],
      webhook.product_id == ^product.id and webhook.name == ^seed.name and
        webhook.source == ^seed.source
    )
    |> Repo.exists?()

  unless exists? do
    {:ok, {_webhook, token}} =
      Webhooks.create(product, %{
        "name" => seed.name,
        "source" => Atom.to_string(seed.source)
      })

    IO.puts(
      "Seeded webhook for #{seed.product_name} (#{seed.source}). Token (shown once): #{token}"
    )
  end
end)

grafana_alert_seeds = [
  %{
    product_name: "Hive",
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
    product_name: "Hive",
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
    product_name: "Tuist",
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
    product_name: "Tuist",
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
  product = Repo.get_by!(Product, name: seed.product_name)

  webhook =
    Repo.one!(
      from webhook in Webhook,
        where: webhook.product_id == ^product.id and webhook.source == ^:grafana,
        limit: 1
    )

  {:ok, _alerts} = Grafana.ingest(product, webhook, seed.payload)
end)
