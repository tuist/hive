import Ecto.Query

alias Hive.Accounts
alias Hive.Accounts.UserIdentity
alias Hive.Forage
alias Hive.Forage.FeatureRequest
alias Hive.Products
alias Hive.Products.Product
alias Hive.Repo

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
    "github_repository_owner" => "tuist",
    "github_repository_name" => "hive"
  },
  %{
    "name" => "Tuist",
    "description" =>
      "Developer tools for generating, maintaining, and optimizing Xcode projects.",
    "github_repository_owner" => "tuist",
    "github_repository_name" => "tuist"
  },
  %{
    "name" => "Noora",
    "description" => "Design system components shared across Tuist products.",
    "github_repository_owner" => "tuist",
    "github_repository_name" => "tuist"
  },
  %{
    "name" => "Atlas",
    "description" => "A product boundary without a GitHub repository connected yet."
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
