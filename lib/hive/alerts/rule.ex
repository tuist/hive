defmodule Hive.Alerts.Rule do
  @moduledoc """
  A per-project rule that turns a signal from a supported source into a
  notification on a chosen destination.

  For v1 the only source is `:error_issue` (Hive's error tracking).
  Two destination types are supported: `:slack` posts to a channel on
  an installed Hive workspace; `:webhook` POSTs a signed JSON envelope
  to any HTTPS endpoint (Grafana, PagerDuty, a bespoke receiver).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Alerts.Notification
  alias Hive.Projects.Project
  alias Hive.Slack.Installation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sources [:error_issue]
  @triggers [:new_issue_threshold, :regression]
  @tiers [:attention, :incident]
  @levels [:fatal, :error, :warning, :info, :debug]
  @mentions [:none, :here, :channel]
  @destination_types [:slack, :webhook]

  schema "alert_rules" do
    field :name, :string
    field :source, Ecto.Enum, values: @sources, default: :error_issue
    field :trigger, Ecto.Enum, values: @triggers
    field :tier, Ecto.Enum, values: @tiers, default: :attention
    field :enabled, :boolean, default: true

    field :threshold_event_count, :integer
    field :threshold_window_minutes, :integer

    field :min_level, Ecto.Enum, values: @levels
    field :environment, :string

    field :cooldown_minutes, :integer, default: 60

    field :destination_type, Ecto.Enum, values: @destination_types, default: :slack
    field :slack_channel_id, :string
    field :slack_mention, Ecto.Enum, values: @mentions, default: :none
    field :webhook_url, :string
    field :webhook_signing_secret, :string

    belongs_to :project, Project
    belongs_to :slack_installation, Installation
    has_many :notifications, Notification, foreign_key: :rule_id

    timestamps(type: :utc_datetime)
  end

  def sources, do: @sources
  def triggers, do: @triggers
  def tiers, do: @tiers
  def levels, do: @levels
  def mentions, do: @mentions
  def destination_types, do: @destination_types

  @doc """
  Generates a fresh signing secret suitable for the `webhook_signing_secret`
  field. Written when a webhook destination is created; the receiver uses
  it to verify the HMAC signature on incoming envelopes.
  """
  def generate_webhook_signing_secret do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :project_id,
      :name,
      :source,
      :trigger,
      :tier,
      :enabled,
      :threshold_event_count,
      :threshold_window_minutes,
      :min_level,
      :environment,
      :cooldown_minutes,
      :destination_type,
      :slack_installation_id,
      :slack_channel_id,
      :slack_mention,
      :webhook_url,
      :webhook_signing_secret
    ])
    |> validate_required([:project_id, :name, :trigger, :tier, :source, :destination_type])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_number(:cooldown_minutes, greater_than_or_equal_to: 0)
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:trigger, @triggers)
    |> validate_inclusion(:tier, @tiers)
    |> validate_inclusion(:destination_type, @destination_types)
    |> validate_threshold_fields()
    |> validate_destination()
  end

  # `new_issue_threshold` needs both a count and a window; other triggers
  # ignore them. We clear the fields when they do not apply so the row
  # does not carry stale values from a previous edit.
  defp validate_threshold_fields(changeset) do
    case get_field(changeset, :trigger) do
      :new_issue_threshold ->
        changeset
        |> put_change_default(:threshold_event_count, 5)
        |> put_change_default(:threshold_window_minutes, 60)
        |> validate_number(:threshold_event_count, greater_than: 0)
        |> validate_number(:threshold_window_minutes, greater_than: 0)

      _other ->
        changeset
        |> put_change(:threshold_event_count, nil)
        |> put_change(:threshold_window_minutes, nil)
    end
  end

  defp put_change_default(changeset, field, default) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, default)
      _value -> changeset
    end
  end

  defp validate_destination(changeset) do
    case get_field(changeset, :destination_type) do
      :slack -> validate_slack_destination(changeset)
      :webhook -> validate_webhook_destination(changeset)
      _other -> changeset
    end
  end

  defp validate_slack_destination(changeset) do
    changeset =
      changeset
      |> put_change(:webhook_url, nil)
      |> put_change(:webhook_signing_secret, nil)

    installation_id = get_field(changeset, :slack_installation_id)
    channel_id = get_field(changeset, :slack_channel_id)

    cond do
      is_nil(installation_id) ->
        add_error(changeset, :slack_installation_id, "pick a Slack workspace")

      blank?(channel_id) ->
        add_error(changeset, :slack_channel_id, "pick a Slack channel to send the alert to")

      true ->
        changeset
    end
  end

  defp validate_webhook_destination(changeset) do
    changeset =
      changeset
      |> put_change(:slack_installation_id, nil)
      |> put_change(:slack_channel_id, nil)
      |> put_change(:slack_mention, :none)
      |> ensure_webhook_signing_secret()

    url = get_field(changeset, :webhook_url)

    cond do
      blank?(url) ->
        add_error(changeset, :webhook_url, "enter an HTTPS URL to POST alerts to")

      not valid_webhook_url?(url) ->
        add_error(changeset, :webhook_url, "must be a valid http(s) URL")

      true ->
        changeset
    end
  end

  defp ensure_webhook_signing_secret(changeset) do
    case get_field(changeset, :webhook_signing_secret) do
      value when is_binary(value) and byte_size(value) > 0 -> changeset
      _ -> put_change(changeset, :webhook_signing_secret, generate_webhook_signing_secret())
    end
  end

  defp valid_webhook_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  defp valid_webhook_url?(_), do: false

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
