defmodule Hive.Forage.Grafana do
  @moduledoc """
  Parses Grafana Unified Alerting webhook payloads and upserts the
  resulting alerts into `forage_grafana_alerts`, keyed by
  `(project_id, fingerprint)` so firing/resolved deliveries thread into
  the same row.

  Reference payload shape (only the fields Hive uses):

      {
        "status": "firing" | "resolved",
        "alerts": [
          {
            "status": "firing" | "resolved",
            "fingerprint": "abc123",
            "labels": {"alertname": "HighLatency", ...},
            "annotations": {"summary": "...", "description": "..."},
            "startsAt": "...",
            "endsAt": "...",
            "generatorURL": "..."
          }
        ]
      }
  """

  import Ecto.Query

  alias Hive.Forage.GrafanaAlert
  alias Hive.Projects.Project
  alias Hive.Projects.Webhook
  alias Hive.Repo

  @doc """
  Ingests a parsed JSON payload from Grafana. Returns
  `{:ok, [%GrafanaAlert{}, ...]}` listing the upserted rows, or
  `{:error, :invalid_payload}` if the payload doesn't look like Grafana.
  """
  def ingest(%Project{} = project, %Webhook{} = webhook, payload) when is_map(payload) do
    case extract_alerts(payload) do
      [] ->
        {:error, :invalid_payload}

      alerts ->
        {:ok, Enum.map(alerts, &upsert_alert(project, webhook, &1))}
    end
  end

  def ingest(_project, _webhook, _payload), do: {:error, :invalid_payload}

  defp extract_alerts(%{"alerts" => alerts}) when is_list(alerts), do: alerts
  defp extract_alerts(_payload), do: []

  defp upsert_alert(%Project{} = project, %Webhook{} = webhook, alert) when is_map(alert) do
    fingerprint = Map.get(alert, "fingerprint") || derive_fingerprint(alert)
    status = parse_status(Map.get(alert, "status"))
    labels = alert |> Map.get("labels") || %{}
    annotations = alert |> Map.get("annotations") || %{}
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      fingerprint: fingerprint,
      status: status,
      title: derive_title(labels, annotations),
      summary: derive_summary(annotations),
      generator_url: Map.get(alert, "generatorURL"),
      labels: labels,
      starts_at: parse_timestamp(Map.get(alert, "startsAt")),
      ends_at: parse_timestamp(Map.get(alert, "endsAt")),
      last_received_at: now,
      project_id: project.id,
      webhook_id: webhook.id
    }

    case Repo.get_by(GrafanaAlert, project_id: project.id, fingerprint: fingerprint) do
      nil -> %GrafanaAlert{}
      existing -> existing
    end
    |> GrafanaAlert.changeset(attrs)
    |> Repo.insert_or_update!()
  end

  defp parse_status("firing"), do: :firing
  defp parse_status("resolved"), do: :resolved
  defp parse_status(_), do: :firing

  defp derive_title(labels, annotations) do
    Map.get(annotations, "summary") || Map.get(labels, "alertname") || "Grafana alert"
  end

  defp derive_summary(annotations) do
    Map.get(annotations, "description") || Map.get(annotations, "message")
  end

  defp derive_fingerprint(alert) do
    payload = alert |> Map.take(["labels", "annotations", "generatorURL"]) |> Jason.encode!()

    :sha256
    |> :crypto.hash(payload)
    |> Base.encode16(case: :lower)
  end

  defp parse_timestamp(nil), do: nil
  defp parse_timestamp(""), do: nil

  defp parse_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        dt = DateTime.truncate(dt, :second)
        if epoch?(dt), do: nil, else: dt

      _ ->
        nil
    end
  end

  defp parse_timestamp(_value), do: nil

  defp epoch?(%DateTime{year: 1, month: 1, day: 1}), do: true
  defp epoch?(_), do: false

  @doc """
  Lists all Grafana alerts most-recent-first, preloading their project
  and optional domain.
  """
  def list_alerts do
    GrafanaAlert
    |> order_by([alert], desc: alert.last_received_at)
    |> preload([:project, :domain])
    |> Repo.all()
  end

  @doc """
  Lists Grafana alerts classified into a single domain,
  most-recent-first.
  """
  def list_alerts_for_domain(domain_id) when is_binary(domain_id) do
    GrafanaAlert
    |> where([alert], alert.domain_id == ^domain_id)
    |> order_by([alert], desc: alert.last_received_at)
    |> preload([:project, :domain])
    |> Repo.all()
  end
end
