defmodule Hive.Integrations.GitHubApp do
  use Hive.Schema
  import Ecto.Changeset

  schema "github_apps" do
    field :name, :string
    field :webhook_secret, :string

    has_many :repositories, Hive.Integrations.GitHubRepository, foreign_key: :github_app_id

    timestamps()
  end

  def changeset(app, attrs) do
    app
    |> cast(attrs, [:name, :webhook_secret])
    |> validate_required([:name, :webhook_secret])
  end
end
