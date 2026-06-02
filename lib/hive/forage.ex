defmodule Hive.Forage do
  @moduledoc """
  Collects sources that can feed Hive with workable pieces of work.
  """

  import Ecto.Query

  alias Hive.Accounts.User
  alias Hive.Auth
  alias Hive.Forage.FeatureRequest
  alias Hive.Repo

  @sources [
    %{
      id: :feature_requests,
      label: "Feature requests",
      description: "Public product ideas submitted by authenticated users.",
      icon: "bulb",
      path: "/forage/feature-requests",
      visibility: :public,
      creatable?: true
    },
    %{
      id: :bug_reports,
      label: "Bug reports",
      description: "Public defects that should become actionable work.",
      icon: "file_alert",
      path: "/forage/bug-reports",
      visibility: :public,
      creatable?: true
    },
    %{
      id: :feedback,
      label: "Feedback",
      description: "Public feedback that helps shape the product direction.",
      icon: "message_circle",
      path: "/forage/feedback",
      visibility: :public,
      creatable?: true
    },
    %{
      id: :grafana_alerts,
      label: "Grafana alerts",
      description: "Operational signals visible only to organization members.",
      icon: "bell",
      path: "/forage/grafana-alerts",
      visibility: :organization,
      creatable?: false
    }
  ]

  def sources, do: @sources

  def visible_sources(user) do
    Enum.filter(@sources, &can_access?(&1, user))
  end

  def get_source!(id) do
    Enum.find(@sources, &(&1.id == id)) || raise ArgumentError, "unknown forage source: #{id}"
  end

  def can_access?(%{visibility: :public}, _user), do: true
  def can_access?(%{visibility: :organization}, user), do: Auth.member?(user)

  def can_create?(source, user) do
    source.creatable? and can_access?(source, user)
  end

  def list_feature_requests do
    FeatureRequest
    |> order_by([feature_request], desc: feature_request.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  def change_feature_request(feature_request \\ %FeatureRequest{}, attrs \\ %{}) do
    FeatureRequest.changeset(feature_request, attrs)
  end

  def create_feature_request(attrs, %User{} = user) do
    %FeatureRequest{}
    |> FeatureRequest.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> Repo.insert()
  end
end
