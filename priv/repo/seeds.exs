import Ecto.Query

alias Hive.Accounts
alias Hive.Accounts.UserIdentity
alias Hive.Audit
alias Hive.Audit.Activity
alias Hive.Forage
alias Hive.Forage.FeatureRequest
alias Hive.Forage.Grafana
alias Hive.Domains
alias Hive.Domains.GitHubRepository
alias Hive.Domains.Domain
alias Hive.Projects
alias Hive.Projects.Project
alias Hive.Projects.Webhook
alias Hive.Projects.Webhooks
alias Hive.Repo
alias Hive.Specs
alias Hive.Specs.Comment
alias Hive.Specs.Revision
alias Hive.Specs.Spec
alias Hive.Specs.View, as: SpecView

defmodule Hive.Repo.Seeds do
  @moduledoc false

  alias Hive.Accounts
  alias Hive.Accounts.User
  alias Hive.Inference
  alias Hive.Inference.ModelBinding
  alias Hive.Inference.Provider
  alias Hive.Inference.Token
  alias Hive.Inference.Usage
  alias Hive.Repo
  alias Hive.Slack
  alias Hive.Slack.Installation
  alias Hive.Slack.NotificationRoute

  import Ecto.Query

  def user!(email, opts \\ []) do
    provider = Keyword.get(opts, :provider, "seed")
    provider_uid = Keyword.get(opts, :provider_uid, email)
    name = Keyword.get(opts, :name)

    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: email,
        name: name,
        provider: provider,
        provider_uid: provider_uid
      })

    maybe_update_user_name(user, name)
  end

  def update_role!(email, role) do
    case Accounts.get_user_by_email(email) do
      nil ->
        :ok

      user ->
        {:ok, _user} = Accounts.update_user_role(user, role)
        :ok
    end
  end

  def inference_profile!(attrs) do
    name = Map.fetch!(attrs, :name)

    case Inference.get_model_binding_by_name(name) do
      nil ->
        {:ok, profile} = Inference.create_profile(attrs)
        profile

      %ModelBinding{} = profile ->
        {:ok, profile} = Inference.update_profile(profile, attrs)
        profile
    end
  end

  def inference_provider!(attrs) do
    key = Map.fetch!(attrs, :key)

    case Inference.get_provider_by_key(key) do
      nil ->
        {:ok, provider} = Inference.create_provider(attrs)
        provider

      %Provider{} = provider ->
        {:ok, provider} =
          provider
          |> Provider.changeset(attrs)
          |> Repo.update()

        provider
    end
  end

  def inference_token!(%ModelBinding{id: profile_id} = profile, attrs) do
    name = Map.fetch!(attrs, :name)

    case Repo.get_by(Token, model_binding_id: profile_id, name: name) do
      nil ->
        {:ok, {token, _token_value}} = Inference.create_profile_token(profile, attrs)
        token

      %Token{} = token ->
        {:ok, token} =
          token
          |> Token.changeset(Map.take(attrs, [:name, :enabled, :expires_at]))
          |> Repo.update()

        token
    end
  end

  def revoke_token!(%Token{enabled: false} = token), do: token

  def revoke_token!(%Token{} = token) do
    {:ok, token} = Inference.revoke_token(token)
    token
  end

  def seed_inference_profiles!(profile_seeds) do
    Enum.each(profile_seeds, &seed_inference_profile!/1)
  end

  def seed_inference_profile!(seed) do
    profile =
      seed.profile
      |> Map.put_new(:hive_inference, false)
      |> Map.put_new(:hive_embedding, false)
      |> inference_profile!()

    seeded_tokens =
      seed
      |> inference_token_seeds()
      |> Enum.map(&seed_inference_token!(profile, &1))

    reset_inference_usage!(Enum.map(seeded_tokens, fn {token, _seed} -> token end))

    Enum.each(seeded_tokens, fn {token, token_seed} ->
      seed_inference_usage!(
        profile,
        token,
        Map.get(token_seed, :usage, []),
        Map.fetch!(seed, :rates)
      )
    end)

    profile
  end

  def reset_inference_usage!([]), do: :ok

  def reset_inference_usage!(tokens) do
    token_ids = Enum.map(tokens, & &1.id)

    Usage
    |> where([usage], usage.token_id in ^token_ids)
    |> Repo.delete_all()
  end

  def slack_installation!(attrs) do
    team_id = Map.fetch!(attrs, :team_id)

    installation =
      case Repo.get_by(Installation, team_id: team_id) do
        nil ->
          %Installation{}
          |> Installation.changeset(attrs)
          |> Repo.insert!()

        %Installation{} = installation ->
          installation
          |> Installation.changeset(attrs)
          |> Repo.update!()
      end

    Repo.preload(installation, [:installed_by_user, :notification_routes])
  end

  def slack_notification_route!(%Installation{} = installation, attrs) do
    object_type = Map.fetch!(attrs, :object_type)

    route =
      Slack.notification_routes()
      |> Enum.find(&(&1.object_type == object_type))
      |> case do
        nil -> raise "unknown Slack notification route #{inspect(object_type)}"
        route -> route
      end

    attrs =
      attrs
      |> Map.put(:installation_id, installation.id)
      |> Map.put_new(:notification_events, route.events)

    allowed_object_types = Enum.map(Slack.notification_routes(), & &1.object_type)

    case Repo.get_by(NotificationRoute,
           installation_id: installation.id,
           object_type: object_type
         ) do
      nil ->
        %NotificationRoute{}
        |> NotificationRoute.changeset(attrs, allowed_object_types, Slack.notification_events())
        |> Repo.insert!()

      %NotificationRoute{} = notification_route ->
        notification_route
        |> NotificationRoute.changeset(attrs, allowed_object_types, Slack.notification_events())
        |> Repo.update!()
    end
  end

  def seed_inference_usage!(%ModelBinding{} = profile, %Token{} = token, points, rates) do
    Enum.each(points, fn point ->
      input_tokens = Map.fetch!(point, :input_tokens)
      output_tokens = Map.fetch!(point, :output_tokens)

      Repo.insert!(%Usage{
        operation: usage_operation(point),
        model_binding_id: profile.id,
        token_id: token.id,
        upstream_provider: profile.upstream_provider,
        upstream_model: profile.upstream_model,
        status: Map.get(point, :status, 200),
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        total_tokens: input_tokens + output_tokens,
        cost_usd: usage_cost_usd(input_tokens, output_tokens, rates),
        inserted_at: Map.fetch!(point, :at)
      })
    end)

    case latest_usage_at(points) do
      nil ->
        :ok

      latest_at ->
        {:ok, _token} = Token.changeset(token, %{last_used_at: latest_at}) |> Repo.update()
        profile = Repo.get!(ModelBinding, profile.id)

        last_used_at =
          case profile.last_used_at do
            nil ->
              latest_at

            current ->
              if DateTime.compare(current, latest_at) == :lt, do: latest_at, else: current
          end

        {:ok, _profile} =
          ModelBinding.changeset(profile, %{last_used_at: last_used_at}) |> Repo.update()

        :ok
    end
  end

  def inference_usage_points(days, input_base, output_base, offset \\ 0) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    0..(days - 1)
    |> Enum.flat_map(fn index ->
      days_ago = days - index - 1
      multiplier = 1 + rem(index + offset, 5)

      primary = %{
        at: DateTime.add(now, -days_ago, :day),
        input_tokens: input_base + multiplier * 720 + rem(index * 97 + offset, 800),
        output_tokens: output_base + multiplier * 360 + rem(index * 53 + offset, 500)
      }

      if rem(index + offset, 4) == 0 do
        [
          primary,
          %{
            at: DateTime.add(primary.at, -6, :hour),
            input_tokens: div(input_base, 2) + multiplier * 410,
            output_tokens: div(output_base, 2) + multiplier * 220
          }
        ]
      else
        [primary]
      end
    end)
  end

  def inference_embedding_usage_points(days, input_base, offset \\ 0) do
    days
    |> inference_usage_points(input_base, 0, offset)
    |> Enum.map(&Map.merge(&1, %{operation: :embedding, output_tokens: 0}))
  end

  defp inference_token_seeds(seed) do
    repository_tokens =
      seed
      |> Map.get(:tokens, [])
      |> Enum.map(&{:repository, &1})

    hive_tokens =
      seed
      |> Map.get(:hive_tokens, [])
      |> Enum.map(&{:hive, &1})

    repository_tokens ++ hive_tokens
  end

  defp seed_inference_token!(%ModelBinding{} = profile, {:repository, token_seed}) do
    token_attrs = Map.drop(token_seed, [:usage])
    token = inference_token!(profile, token_attrs)

    unless Map.get(token_attrs, :enabled, true) do
      revoke_token!(token)
    end

    {token, token_seed}
  end

  defp seed_inference_token!(%ModelBinding{} = profile, {:hive, token_seed}) do
    role = Map.fetch!(token_seed, :role)
    {:ok, {token, _token_value}} = Inference.ensure_hive_token(profile, role)

    {token, token_seed}
  end

  defp usage_operation(%{operation: :embedding}), do: "embedding"
  defp usage_operation(%{operation: "embedding"}), do: "embedding"
  defp usage_operation(_point), do: "chat_completion"

  defp latest_usage_at(points) do
    Enum.reduce(points, nil, fn point, latest ->
      at = Map.fetch!(point, :at)

      cond do
        is_nil(latest) -> at
        DateTime.compare(at, latest) == :gt -> at
        true -> latest
      end
    end)
  end

  defp usage_cost_usd(input_tokens, output_tokens, rates) do
    input_cost =
      token_cost_usd(input_tokens, Map.fetch!(rates, :input_cost_per_million))

    output_cost =
      token_cost_usd(output_tokens, Map.fetch!(rates, :output_cost_per_million))

    Decimal.add(input_cost, output_cost)
  end

  defp token_cost_usd(tokens, cost_per_million) do
    tokens
    |> Decimal.new()
    |> Decimal.mult(Decimal.new(cost_per_million))
    |> Decimal.div(Decimal.new(1_000_000))
  end

  defp maybe_update_user_name(user, nil), do: user
  defp maybe_update_user_name(user, ""), do: user
  defp maybe_update_user_name(%User{name: name} = user, name), do: user

  defp maybe_update_user_name(%User{} = user, name) do
    {:ok, user} =
      user
      |> User.changeset(%{name: name})
      |> Repo.update()

    user
  end
end

alias Hive.Repo.Seeds

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
  Seeds.user!(email, provider: provider, provider_uid: provider_uid)
end)

# Keep the local development login useful for admin-only dashboard pages.
Seeds.user!("test@hive.dev",
  provider: "dev",
  provider_uid: "test@hive.dev",
  name: "Hive Admin"
)

Seeds.update_role!("test@hive.dev", :admin)

forage_items = [
  %{
    email: "maya@example.com",
    attrs: %{
      "type" => "feature_request",
      "title" => "Import feature requests from GitHub Discussions",
      "description" =>
        "Let maintainers connect a GitHub Discussions category so public ideas can flow into Forage without copying them by hand."
    }
  },
  %{
    email: "jon@example.com",
    legacy_titles: ["Group forage by source and priority"],
    attrs: %{
      "type" => "bug_report",
      "title" => "Filter forage by type, source, and status",
      "description" =>
        "The unified Forage queue needs stable filters so reviewers can scan feature requests, bug reports, feedback, GitHub issues, and Grafana alerts without jumping between source pages."
    }
  },
  %{
    email: "priya@example.com",
    attrs: %{
      "type" => "feature_request",
      "title" => "Let users subscribe to feature request updates",
      "description" =>
        "Allow authenticated requesters to follow a feature request and receive updates when its status changes."
    }
  },
  %{
    email: "sam@example.com",
    legacy_titles: ["Capture affected organization on public requests"],
    attrs: %{
      "type" => "feedback",
      "title" => "Capture affected organization on public feedback",
      "description" =>
        "When a signed-in user belongs to an organization, attach that organization to the forage item so the team can understand who is asking."
    }
  }
]

Enum.each(forage_items, fn seed ->
  attrs = seed.attrs
  titles = [attrs["title"] | Map.get(seed, :legacy_titles, [])]

  existing_item =
    FeatureRequest
    |> where([feature_request], feature_request.title in ^titles)
    |> Repo.all()
    |> List.first()

  user =
    Seeds.user!(seed.email)

  case existing_item do
    nil ->
      {:ok, _item} = Forage.create_forage_item(attrs, user)

    item ->
      item
      |> FeatureRequest.changeset(attrs)
      |> Ecto.Changeset.put_change(:user_id, user.id)
      |> Repo.update()
  end
end)

# Projects are the top-level grouping. Each project owns repositories
# and links to the reusable domains it slices by.
projects_fixtures = [
  %{
    name: "Tuist",
    description:
      "Developer tooling for Xcode projects, continuous integration, caching, and app delivery.",
    visibility: "public",
    repositories: [%{owner: "tuist", name: "tuist", visibility: "public"}],
    domains: [
      %{
        name: "Tuist",
        description: "Anything Tuist-wide that does not fit a narrower domain.",
        visibility: "public"
      },
      %{
        name: "CLI",
        description: "Command line interface to interact with the Tuist platform.",
        visibility: "public"
      },
      %{
        name: "Cache",
        description: "Tuist's caching functionality.",
        visibility: "public"
      },
      %{
        name: "Compute",
        description:
          "Tuist's runner compute infrastructure including Linux and macOS Kubernetes pools, gateway proxies, sandbox APIs, kubectl access gateways, and account-scoped execution environments for development.",
        visibility: "public"
      },
      %{
        name: "Distribution",
        description:
          "Artifact publication, release workflows, dependency management, and distribution channels that make Tuist available to users.",
        visibility: "public"
      },
      %{
        name: "Generated projects",
        description: "Tuist's client-side technology for Xcode projects.",
        visibility: "public"
      }
    ]
  },
  %{
    name: "Atlas",
    description: "Tuist's agentic operations platform.",
    visibility: "public",
    repositories: [%{owner: "tuist", name: "atlas", visibility: "public"}],
    domains: [
      %{
        name: "Atlas",
        description: "Agentic operations workflows for Tuist.",
        visibility: "public"
      }
    ]
  },
  %{
    name: "Hive",
    description: "Agentic product development including planning, forage, specs, and drops.",
    visibility: "public",
    repositories: [%{owner: "tuist", name: "hive", visibility: "public"}],
    domains: [
      %{name: "Hive", description: "All Hive updates.", visibility: "public"}
    ]
  },
  %{
    name: "Kura",
    description: "Tuist's Kura product surface.",
    visibility: "public",
    repositories: [%{owner: "tuist", name: "kura", visibility: "public"}],
    domains: [
      %{name: "Kura", description: "All Kura updates.", visibility: "public"}
    ]
  },
  %{
    name: "Noora",
    description: "Tuist's design system.",
    visibility: "public",
    repositories: [%{owner: "tuist", name: "noora", visibility: "public"}],
    domains: [
      %{name: "Noora", description: "All Noora updates.", visibility: "public"}
    ]
  },
  %{
    name: "Once",
    description: "Installable Tuist products that people can run in their own infrastructure.",
    visibility: "public",
    repositories: [%{owner: "tuist", name: "once", visibility: "public"}],
    domains: [
      %{
        name: "Once",
        description: "Self-hosted distribution and operations.",
        visibility: "public"
      }
    ]
  }
]

Enum.each(projects_fixtures, fn fixture ->
  project =
    case Projects.list_projects() |> Enum.find(&(&1.name == fixture.name)) do
      nil ->
        {:ok, project} =
          Projects.create_project(%{
            name: fixture.name,
            description: fixture.description,
            visibility: fixture.visibility
          })

        project

      project ->
        {:ok, project} =
          Projects.update_project(project, %{
            name: fixture.name,
            description: fixture.description,
            visibility: fixture.visibility
          })

        project
    end

  Enum.each(fixture.repositories, fn repo_attrs ->
    case Repo.get_by(GitHubRepository, owner: repo_attrs.owner, name: repo_attrs.name) do
      nil ->
        %GitHubRepository{}
        |> GitHubRepository.changeset(Map.put(repo_attrs, :project_id, project.id))
        |> Repo.insert!()

      existing ->
        existing
        |> GitHubRepository.changeset(Map.put(repo_attrs, :project_id, project.id))
        |> Repo.update!()
    end
  end)

  Enum.each(fixture.domains, fn domain_attrs ->
    attrs = Map.put(domain_attrs, :project_id, project.id)

    domain =
      case Repo.get_by(Domain, name: domain_attrs.name) do
        nil ->
          {:ok, domain} = Domains.create_domain(attrs)
          domain

        domain ->
          {:ok, domain} = Domains.update_domain(domain, attrs)
          domain
      end

    Domains.link_domain_to_project(domain, project.id)
  end)
end)

[
  %{
    key: "fireworks",
    base_url: "https://api.fireworks.ai/inference/v1",
    api_key: "development-fireworks-placeholder",
    timeout: 300_000
  },
  %{
    key: "openai",
    base_url: "https://api.openai.com/v1",
    api_key: "development-openai-placeholder",
    timeout: 300_000
  }
]
|> Enum.each(&Seeds.inference_provider!/1)

inference_profiles = [
  %{
    rates: %{input_cost_per_million: "0.15", output_cost_per_million: "0.60"},
    profile: %{
      name: "blick-code-review",
      description:
        "Repository code review profile used by Blick through opencode. Repositories keep this stable name while Hive can retarget the upstream model.",
      upstream_provider: "fireworks",
      upstream_model: "accounts/fireworks/models/kimi-k2p5",
      input_cost_per_million: "0.15",
      output_cost_per_million: "0.60",
      enabled: true
    },
    tokens: [
      %{
        name: "Tuist repositories",
        enabled: true,
        expires_at: nil,
        usage: Seeds.inference_usage_points(30, 10_400, 2_900, 1)
      },
      %{
        name: "Hive repositories",
        enabled: true,
        expires_at: nil,
        usage: Seeds.inference_usage_points(30, 6_800, 1_900, 3)
      },
      %{
        name: "Noora repositories",
        enabled: true,
        expires_at: nil,
        usage: Seeds.inference_usage_points(18, 4_200, 1_350, 5)
      }
    ]
  },
  %{
    rates: %{input_cost_per_million: "0.15", output_cost_per_million: "0.60"},
    profile: %{
      name: "hive-agent-runtime",
      description:
        "Runtime profile selected for Hive's own agentic workflows. Hive calls this profile through its OpenAI-compatible gateway with a Hive-owned token.",
      upstream_provider: "openai",
      upstream_model: "gpt-4o-mini",
      input_cost_per_million: "0.15",
      output_cost_per_million: "0.60",
      enabled: false,
      hive_inference: true
    },
    hive_tokens: [
      %{
        role: :inference,
        usage: Seeds.inference_usage_points(21, 8_400, 2_200, 11)
      }
    ],
    tokens: [
      %{
        name: "Local gateway smoke tests",
        enabled: true,
        expires_at: nil,
        usage: Seeds.inference_usage_points(10, 2_400, 700, 16)
      }
    ]
  },
  %{
    rates: %{input_cost_per_million: "0.02", output_cost_per_million: "0.00"},
    profile: %{
      name: "hive-embeddings-runtime",
      description:
        "Embedding profile reserved for Hive workflows that need vectors. It uses the same gateway, attribution, and cost reporting as chat profiles.",
      upstream_provider: "fireworks",
      upstream_model: "accounts/fireworks/models/qwen3-embedding-8b",
      input_cost_per_million: "0.02",
      output_cost_per_million: "0.00",
      enabled: true,
      hive_embedding: true
    },
    hive_tokens: [
      %{
        role: :embedding,
        usage: Seeds.inference_embedding_usage_points(21, 18_000, 19)
      }
    ]
  },
  %{
    rates: %{input_cost_per_million: "0.15", output_cost_per_million: "0.60"},
    profile: %{
      name: "spec-drafting-experiment",
      description:
        "Disabled sample profile for experimenting with repository-local spec drafting without changing production tokens.",
      upstream_provider: "openai",
      upstream_model: "gpt-4o-mini",
      input_cost_per_million: "0.15",
      output_cost_per_million: "0.60",
      enabled: false
    },
    tokens: [
      %{
        name: "Retired local experiment",
        enabled: false,
        expires_at: nil,
        usage: Seeds.inference_usage_points(12, 3_200, 2_600, 8)
      }
    ]
  }
]

Seeds.seed_inference_profiles!(inference_profiles)

slack_admin = Accounts.get_user_by_email("test@hive.dev")

slack_installation_seeds = [
  %{
    installation: %{
      team_id: "T-SEED-TUIST-COMMUNITY",
      team_name: "Tuist Community",
      bot_user_id: "U-SEED-HIVE-BOT",
      bot_token: nil,
      scope: Enum.join(Hive.Slack.default_bot_scopes(), ","),
      installed_at: ~U[2026-06-18 09:00:00Z],
      disconnected_at: ~U[2026-06-18 09:00:00Z],
      installed_by_user_id: slack_admin && slack_admin.id
    },
    routes: [
      %{
        object_type: "specs",
        slack_channel_id: "C0123456789"
      }
    ]
  },
  %{
    installation: %{
      team_id: "T-SEED-TUIST-COMPANY",
      team_name: "Tuist Company",
      bot_user_id: "U-SEED-HIVE-BOT",
      bot_token: nil,
      scope: Enum.join(Hive.Slack.default_bot_scopes(), ","),
      installed_at: ~U[2026-06-17 14:30:00Z],
      disconnected_at: ~U[2026-06-17 14:30:00Z],
      installed_by_user_id: slack_admin && slack_admin.id
    },
    routes: [
      %{
        object_type: "specs",
        slack_channel_id: "C9876543210"
      }
    ]
  },
  %{
    installation: %{
      team_id: "T-SEED-ARCHIVE",
      team_name: "Archived workspace",
      bot_user_id: "U-SEED-HIVE-BOT",
      bot_token: nil,
      scope: Enum.join(Hive.Slack.default_bot_scopes(), ","),
      installed_at: ~U[2026-06-10 12:00:00Z],
      disconnected_at: ~U[2026-06-20 12:00:00Z],
      installed_by_user_id: slack_admin && slack_admin.id
    },
    routes: []
  }
]

Enum.each(slack_installation_seeds, fn seed ->
  installation = Seeds.slack_installation!(seed.installation)

  Enum.each(seed.routes, fn route_attrs ->
    Seeds.slack_notification_route!(installation, route_attrs)
  end)
end)

drop_fixtures = [
  %{
    domain_name: "Hive",
    source_type: :github_release,
    external_id: "tuist/hive@v0.25.0#slack-ops",
    version: "v0.25.0",
    title: "Slack workspace management moved to Ops",
    body:
      "Admins now manage connected Slack workspaces from the Ops surface at `/ops/slack` instead of the account page. The dashboard sidebar shows an Ops entry so workspace installs are one click away.",
    url: "https://github.com/tuist/hive/releases/tag/v0.25.0",
    published_at: ~U[2026-06-18 09:30:00Z]
  },
  %{
    domain_name: "Hive",
    source_type: :github_release,
    external_id: "tuist/hive@v0.24.0#slack-unfurl",
    version: "v0.24.0",
    title: "Hive links unfurl in Slack threads",
    body:
      "Any spec, forage item, domain, or drop URL pasted into a connected Slack workspace now expands into a rich preview with the title and a short excerpt, so threads stay context-rich without anyone clicking through.",
    url: "https://github.com/tuist/hive/releases/tag/v0.24.0",
    published_at: ~U[2026-06-17 14:00:00Z]
  },
  %{
    domain_name: "Cache",
    source_type: :rss,
    external_id: "https://tuist.dev/changelog/2026-06-15-cache-improvements",
    version: nil,
    title: "Cache hit ratios improved for medium and large workspaces",
    body:
      "Selective testing and binary caching now use a stricter content-addressed hash so unrelated module rebuilds no longer invalidate downstream targets. Expect noticeably fewer rebuilds in workspaces with deep module graphs.",
    url: "https://tuist.dev/changelog/2026-06-15-cache-improvements",
    published_at: ~U[2026-06-15 12:00:00Z]
  },
  %{
    domain_name: "Generated projects",
    source_type: :rss,
    external_id: "https://tuist.dev/changelog/2026-06-10-xcode-26",
    version: "4.7.0",
    title: "Xcode 26 support",
    body:
      "Project generation, caching, and the test runner now recognise Xcode 26's new module map format. Existing manifests don't need any changes; the new format is detected automatically.",
    url: "https://tuist.dev/changelog/2026-06-10-xcode-26",
    published_at: ~U[2026-06-10 10:00:00Z]
  }
]

Enum.each(drop_fixtures, fn fixture ->
  domain =
    Domain
    |> where([m], m.name == ^fixture.domain_name)
    |> Repo.one()

  if domain do
    body = fixture.body

    attrs = %{
      source_type: fixture.source_type,
      external_id: fixture.external_id,
      title: fixture.title,
      body: body,
      url: fixture.url,
      version: fixture.version,
      published_at: fixture.published_at
    }

    {:ok, drop} = Hive.Drops.upsert_drop(attrs)

    Hive.Drops.replace_drop_domains(drop, [domain.id])
  end
end)

github_issue_fixtures = [
  {"tuist", "hive",
   [
     %{
       number: 101,
       title: "Surface unified forage counts on the Forage page",
       body:
         "Show the number of open feature requests, bug reports, GitHub issues, and Grafana alerts in the Forage header so reviewers can scan workload without opening separate pages."
     },
     %{
       number: 102,
       title: "Allow specs to link multiple forage items",
       body:
         "A single spec can be driven by both a feature request and a bug report. Today only one manual forage item can be attached. Capture all of them on the spec detail page."
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
    domain_names: ["Hive"],
    attrs: %{
      "title" => "GitHub Discussions forage import",
      "summary" =>
        "Import public GitHub Discussions into Forage while preserving source metadata for reviewers.",
      "body" => """
      Connect a GitHub Discussions category as a forage source so public domain ideas flow into Hive without manual copying.

      The importer should preserve the original title, body, author signal, and source URL. Imported items should appear alongside manually submitted feature requests and keep enough metadata for reviewers to trace the idea back to GitHub.

      Acceptance criteria:
      - Maintainers can configure one GitHub Discussions category.
      - New discussions become feature request forage items.
      - Existing imported items are not duplicated when the importer runs again.
      """,
      "status" => "proposed"
    },
    comments: [
      {"test@hive.dev",
       "Edit demo: @maya this comment is intentionally a little rough so the inline edit affordance is easy to try locally. It should probably become a short numbered list before asking for another pass."},
      {"jon@example.com",
       "This should keep the source URL visible on the forage item and the spec."},
      {"maya@example.com",
       "@test good catch. When you edit it, try splitting the sync, dedupe, and traceability notes onto separate lines."},
      {"guest@example.com",
       "It would help if imported items linked back to the discussion comments too."}
    ]
  },
  %{
    author: "jon@example.com",
    source_title: "Filter forage by type, source, and status",
    legacy_titles: ["Forage source and priority grouping"],
    domain_names: ["Hive"],
    attrs: %{
      "title" => "Forage type, source, and status filters",
      "summary" =>
        "Filter incoming forage by type, source, status, domain, and repository from one queue.",
      "visibility" => "private",
      "body" => """
      Add lightweight filtering to the unified Forage queue so reviewers can scan incoming work by type, source, status, domain, and repository without jumping between pages.

      The first version should keep the sidebar simple and make the item type, source, and status visible in each row. Alerts remain operational forage that only organization members can see.

      Acceptance criteria:
      - Forage rows show their type, source, status, and domain context.
      - Filter chips, search, and pagination work from `/forage`.
      - Legacy source URLs land on the matching filtered Forage view.
      - Grafana alerts remain hidden from anonymous visitors.
      """,
      "status" => "draft"
    },
    comments: [
      {"priya@example.com",
       "The alert exception is important. Not every signal should become domain planning."}
    ]
  },
  %{
    author: "priya@example.com",
    source_title: "Let users subscribe to feature request updates",
    domain_names: ["Hive"],
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
    domain_names: ["Hive"],
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
    domain_names: ["Hive"],
    attrs: %{
      "title" => "Auto-generate specs from forage with an LLM",
      "summary" =>
        "Convert planned forage items into draft specs automatically using an LLM that fills in the proposal template.",
      "body" => """
      # Proposal

      When a manual forage item is marked `planned`, trigger an LLM to draft a spec body from the item title and description, plus relevant context from the linked domain. The draft is saved as a `draft` spec for a human to refine.

      ## Sketch

      ```elixir
      def draft_spec_from_item(item) do
        prompt = build_prompt(item)
        {:ok, body} = LLM.complete(prompt, model: "claude-opus-4-8")
        Specs.create_spec(%{"title" => item.title, "body" => body, "status" => "draft"}, system_user())
      end
      ```

      ## Why rejected

      > [!CAUTION]
      > We don't have a clear quality signal that the generated drafts would be worth more than the noise they add to the spec list.

      Concretely:

      - No baseline for what "good" looks like: every forage item is different.
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
    domain_names: ["Hive"],
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
  spec = Repo.preload(spec, :domains)
  domain_ids = Map.get(attrs, "domain_ids", [])

  spec.title != attrs["title"] or
    spec.body != attrs["body"] or
    spec.summary != attrs["summary"] or
    Atom.to_string(spec.status) != attrs["status"] or
    Atom.to_string(Specs.effective_visibility(spec)) != Map.get(attrs, "visibility", "public") or
    Enum.sort(Enum.map(spec.domains, & &1.id)) != Enum.sort(domain_ids)
end

Enum.each(specs, fn seed ->
  user = Seeds.user!(seed.author)

  attrs =
    case seed[:source_title] do
      nil ->
        seed.attrs

      source_title ->
        feature_request =
          FeatureRequest
          |> where([feature_request], feature_request.title == ^source_title)
          |> Repo.all()
          |> List.first() ||
            raise "missing seeded forage item titled #{inspect(source_title)}"

        Map.put(seed.attrs, "source_feature_request_id", feature_request.id)
    end
    |> Map.put_new("visibility", "public")
    |> Map.put(
      "domain_ids",
      seed
      |> Map.get(:domain_names, [])
      |> Enum.map(fn name -> Repo.get_by!(Domain, name: name).id end)
    )

  spec_titles = [seed.attrs["title"] | Map.get(seed, :legacy_titles, [])]

  spec =
    case Spec |> where([spec], spec.title in ^spec_titles) |> Repo.all() |> List.first() do
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
        Seeds.user!(author)
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

# Demo spec_views for the dev admin so the "New activity" badge appears on the
# Specs index without manual clicking. Each entry says: "pretend the dev user
# opened this spec on `viewed_at`." If the spec has been updated or commented
# since, the badge shows.
spec_view_seeds = [
  %{
    user_email: "test@hive.dev",
    spec_titles: ["GitHub Discussions forage import"],
    viewed_at: ~U[2020-01-01 00:00:00.000000Z]
  },
  %{
    user_email: "test@hive.dev",
    spec_titles: ["Feature request subscriptions"],
    viewed_at: ~U[2020-01-01 00:00:00.000000Z]
  },
  %{
    user_email: "test@hive.dev",
    spec_titles: ["Spec revision workflow for MCP clients"],
    viewed_at: DateTime.utc_now()
  }
]

Enum.each(spec_view_seeds, fn seed ->
  with %{} = user <- Accounts.get_user_by_email(seed.user_email),
       %Spec{} = spec <-
         Spec |> where([spec], spec.title in ^seed.spec_titles) |> Repo.all() |> List.first() do
    SpecView
    |> where([view], view.user_id == ^user.id and view.spec_id == ^spec.id)
    |> Repo.delete_all()

    %SpecView{}
    |> Ecto.Changeset.cast(
      %{user_id: user.id, spec_id: spec.id, last_viewed_at: seed.viewed_at},
      [:user_id, :spec_id, :last_viewed_at]
    )
    |> Repo.insert!()
  end
end)

project_webhooks = [
  %{project_name: "Hive", name: "Seed Grafana", source: :grafana},
  %{project_name: "Tuist", name: "Seed Grafana", source: :grafana}
]

Enum.each(project_webhooks, fn seed ->
  project = Repo.get_by!(Project, name: seed.project_name)

  exists? =
    Webhook
    |> where(
      [webhook],
      webhook.project_id == ^project.id and webhook.name == ^seed.name and
        webhook.source == ^seed.source
    )
    |> Repo.exists?()

  unless exists? do
    {:ok, {_webhook, token}} =
      Webhooks.create(project, %{
        "name" => seed.name,
        "source" => Atom.to_string(seed.source)
      })

    IO.puts(
      "Seeded webhook for #{seed.project_name} (#{seed.source}). Token (shown once): #{token}"
    )
  end
end)

grafana_alert_seeds = [
  %{
    project_name: "Hive",
    domain_name: "Hive",
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
    project_name: "Hive",
    domain_name: "Hive",
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
    project_name: "Tuist",
    domain_name: "Tuist",
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
    project_name: "Tuist",
    domain_name: "Tuist",
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
  project = Repo.get_by!(Project, name: seed.project_name)
  domain = Repo.get_by(Domain, name: seed.domain_name)

  webhook =
    Repo.one!(
      from webhook in Webhook,
        where: webhook.project_id == ^project.id and webhook.source == ^:grafana,
        limit: 1
    )

  {:ok, alerts} = Grafana.ingest(project, webhook, seed.payload)

  if domain do
    Enum.each(alerts, fn alert ->
      alert
      |> Ecto.Changeset.change(domain_id: domain.id)
      |> Repo.update!()
    end)
  end
end)

# Demo audit activities. Idempotent: each entry is keyed by a stable
# `seed_key` in metadata so re-running seeds replaces rather than duplicates.
demo_actors = %{
  "test@hive.dev" => {"Hive Admin", :admin},
  "maya@example.com" => {"Maya Chen", :member},
  "jon@example.com" => {"Jon Park", :member},
  "priya@example.com" => {"Priya Shah", :member},
  "sam@example.com" => {"Sam Rivera", :member},
  "octo@example.com" => {"Octo Cat", :member}
}

Enum.each(demo_actors, fn {email, {name, role}} ->
  Seeds.user!(email, name: name)
  Seeds.update_role!(email, role)
end)

get_by_title = fn schema, titles ->
  titles = List.wrap(titles)

  schema
  |> where([record], record.title in ^titles)
  |> Repo.all()
  |> List.first()
end

demo_spec =
  get_by_title.(Spec, [
    "Forage type, source, and status filters",
    "Forage source and priority grouping"
  ])

demo_other_spec = Repo.get_by(Spec, title: "GitHub Discussions forage import")
demo_domain = Repo.get_by(Domain, name: "Hive")
demo_tuist_domain = Repo.get_by(Domain, name: "Tuist")

demo_feature_request =
  get_by_title.(FeatureRequest, [
    "Filter forage by type, source, and status",
    "Group forage by source and priority"
  ])

now = DateTime.utc_now() |> DateTime.truncate(:second)
minutes_ago = fn n -> DateTime.add(now, -n * 60, :second) end

audit_seed_entries = [
  %{
    key: "audit-seed-1",
    action: "user.signed_in",
    interface: "dashboard",
    actor: "maya@example.com",
    target_type: "user",
    target_label_from: :actor_email,
    occurred_at: minutes_ago.(3)
  },
  %{
    key: "audit-seed-2",
    action: "spec.updated",
    interface: "dashboard",
    actor: "maya@example.com",
    target_type: "spec",
    target_id: demo_spec && demo_spec.id,
    target_label: demo_spec && demo_spec.title,
    metadata: %{
      "number" => demo_spec && to_string(demo_spec.number),
      "status" => demo_spec && Atom.to_string(demo_spec.status),
      "changed" => %{"status" => "draft", "summary" => "Updated summary"}
    },
    occurred_at: minutes_ago.(8)
  },
  %{
    key: "audit-seed-3",
    action: "spec.commented",
    interface: "dashboard",
    actor: "priya@example.com",
    target_type: "spec",
    target_id: demo_spec && demo_spec.id,
    target_label: demo_spec && demo_spec.title,
    metadata: %{"number" => demo_spec && to_string(demo_spec.number)},
    occurred_at: minutes_ago.(17)
  },
  %{
    key: "audit-seed-4",
    action: "spec.created",
    interface: "mcp",
    actor: "sam@example.com",
    target_type: "spec",
    target_id: demo_other_spec && demo_other_spec.id,
    target_label: demo_other_spec && demo_other_spec.title,
    metadata: %{
      "number" => demo_other_spec && to_string(demo_other_spec.number),
      "source" => "claude-cli"
    },
    occurred_at: minutes_ago.(34)
  },
  %{
    key: "audit-seed-5",
    action: "domain.created",
    interface: "dashboard",
    actor: "test@hive.dev",
    target_type: "domain",
    target_id: demo_domain && demo_domain.id,
    target_label: demo_domain && demo_domain.name,
    occurred_at: minutes_ago.(55)
  },
  %{
    key: "audit-seed-6",
    action: "forage.item_created",
    interface: "dashboard",
    actor: "jon@example.com",
    target_type: "feature_request",
    target_id: demo_feature_request && demo_feature_request.id,
    target_label: demo_feature_request && demo_feature_request.title,
    metadata: %{"type" => "bug_report"},
    occurred_at: minutes_ago.(90)
  },
  %{
    key: "audit-seed-7",
    action: "grafana_alert.received",
    interface: "webhook",
    target_type: "grafana_alert",
    target_id: "seed-hive-latency",
    target_label: "HighRequestLatency",
    metadata: %{"severity" => "critical", "service" => "hive-web"},
    occurred_at: minutes_ago.(120)
  },
  %{
    key: "audit-seed-8",
    action: "github_issue.synced",
    interface: "worker",
    target_type: "github_issue",
    target_id: "101",
    target_label: "Surface unified forage counts on the Forage page",
    metadata: %{"repository" => "tuist/hive", "count" => 3},
    occurred_at: minutes_ago.(180)
  },
  %{
    key: "audit-seed-9",
    action: "spec.updated",
    interface: "mcp",
    actor: "octo@example.com",
    target_type: "spec",
    target_id: demo_other_spec && demo_other_spec.id,
    target_label: demo_other_spec && demo_other_spec.title,
    metadata: %{
      "number" => demo_other_spec && to_string(demo_other_spec.number),
      "changed" => %{"body" => "Refined acceptance criteria"}
    },
    occurred_at: minutes_ago.(260)
  },
  %{
    key: "audit-seed-10",
    action: "project.webhook_received",
    interface: "webhook",
    target_type: "domain",
    target_id: demo_tuist_domain && demo_tuist_domain.id,
    target_label: demo_tuist_domain && demo_tuist_domain.name,
    metadata: %{"source" => "grafana", "alerts" => 1},
    occurred_at: minutes_ago.(420)
  },
  %{
    key: "audit-seed-11",
    action: "user.role_updated",
    interface: "system",
    target_type: "user",
    target_id: "test@hive.dev",
    target_label: "test@hive.dev",
    metadata: %{"from" => "member", "to" => "admin"},
    occurred_at: minutes_ago.(720)
  },
  %{
    key: "audit-seed-12",
    action: "user.signed_out",
    interface: "dashboard",
    actor: "jon@example.com",
    target_type: "user",
    target_label_from: :actor_email,
    occurred_at: minutes_ago.(1440)
  },
  %{
    key: "audit-seed-13",
    action: "spec.created",
    interface: "worker",
    agent: %{name: "IssueTriageAgent", model: "anthropic:claude-haiku-4-5"},
    target_type: "spec",
    target_label: demo_other_spec && demo_other_spec.title,
    metadata: %{
      "number" => demo_other_spec && to_string(demo_other_spec.number),
      "source_issue" => "tuist/hive#101"
    },
    occurred_at: minutes_ago.(70)
  },
  %{
    key: "audit-seed-14",
    action: "forage.item_summarized",
    interface: "worker",
    agent: %{name: "ForageSummarizerAgent", model: "openai:gpt-4o-mini"},
    target_type: "feature_request",
    target_id: demo_feature_request && demo_feature_request.id,
    target_label: demo_feature_request && demo_feature_request.title,
    metadata: %{"summary_chars" => 412, "type" => "bug_report"},
    occurred_at: minutes_ago.(210)
  }
]

Enum.each(audit_seed_entries, fn entry ->
  Activity
  |> where([a], fragment("?->>'seed_key' = ?", a.metadata, ^entry.key))
  |> Repo.delete_all()

  user_actor = entry[:actor] && Accounts.get_user_by_email(entry[:actor])

  agent_actor =
    case entry[:agent] do
      %{name: name} = agent -> Audit.agent_actor(name, model: Map.get(agent, :model))
      _other -> nil
    end

  actor = agent_actor || user_actor

  metadata =
    entry
    |> Map.get(:metadata, %{})
    |> Map.put("seed_key", entry.key)

  target_label =
    case entry[:target_label_from] do
      :actor_email -> user_actor && user_actor.email
      _ -> entry[:target_label]
    end

  Audit.log(entry.action, %{
    actor: actor,
    interface: entry.interface,
    occurred_at: entry.occurred_at,
    target_type: entry[:target_type],
    target_id: entry[:target_id],
    target_label: target_label,
    metadata: metadata
  })
end)
