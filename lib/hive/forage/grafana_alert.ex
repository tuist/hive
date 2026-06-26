defmodule Hive.Forage.GrafanaAlert do
  @moduledoc """
  A Grafana alert ingested via an inbound project webhook.

  One row per Grafana `fingerprint` per project. Firing and resolved
  deliveries for the same fingerprint update the same row, so the UI can
  thread state transitions instead of stacking duplicate cards.
  """

  use Ecto.Schema
  use Gettext, backend: HiveWeb.Gettext

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:firing, :resolved]

  schema "forage_grafana_alerts" do
    field :fingerprint, :string
    field :status, Ecto.Enum, values: @statuses
    field :title, :string
    field :summary, :string
    field :generator_url, :string
    field :labels, :map, default: %{}
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :last_received_at, :utc_datetime

    belongs_to :project, Hive.Projects.Project
    belongs_to :domain, Hive.Domains.Domain
    belongs_to :webhook, Hive.Projects.Webhook

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def status_label(:firing), do: dgettext("dashboard_forage", "Firing")
  def status_label(:resolved), do: dgettext("dashboard_forage", "Resolved")

  def status_color(:firing), do: "attention"
  def status_color(:resolved), do: "success"

  @doc false
  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [
      :fingerprint,
      :status,
      :title,
      :summary,
      :generator_url,
      :labels,
      :starts_at,
      :ends_at,
      :last_received_at,
      :project_id,
      :domain_id,
      :webhook_id
    ])
    |> validate_required([
      :fingerprint,
      :status,
      :title,
      :last_received_at,
      :project_id
    ])
    |> validate_length(:title, max: 255)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:project_id, :fingerprint])
  end
end
