import Ecto.Query

alias Hive.Accounts
alias Hive.Forage
alias Hive.Forage.FeatureRequest
alias Hive.Repo

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
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: email,
        provider: "seed",
        provider_uid: email
      })

    {:ok, _feature_request} = Forage.create_feature_request(attrs, user)
  end
end)
