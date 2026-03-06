defmodule Hive.Integrations.GitHubApp do
  use Hive.Schema
  import Ecto.Changeset

  schema "github_apps" do
    field :name, :string
    field :webhook_secret, :string
    field :app_id, :string
    field :private_key, :string
    field :installation_id, :string

    has_many :repositories, Hive.Integrations.GitHubRepository, foreign_key: :github_app_id

    timestamps()
  end

  def changeset(app, attrs) do
    app
    |> cast(attrs, [:name, :webhook_secret, :app_id, :private_key, :installation_id])
    |> validate_required([:name, :webhook_secret, :app_id, :private_key, :installation_id])
  end
end
