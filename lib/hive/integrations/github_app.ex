defmodule Hive.Integrations.GitHubApp do
  use Hive.Schema
  import Ecto.Changeset

  schema "github_apps" do
    field :name, :string
    field :webhook_secret, Hive.Encrypted.Binary
    field :app_id, :string
    field :private_key, Hive.Encrypted.Binary
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
