defmodule HiveWeb.ProjectWebhookController do
  @moduledoc """
  Inbound webhook for project-scoped sources.

  The URL carries the project id, the source key, and a per-webhook
  token: `/webhooks/projects/:project_id/:source/:token`.
  """

  use HiveWeb, :controller

  alias Hive.Projects
  alias Hive.Projects.Project
  alias Hive.Projects.Webhook
  alias Hive.Projects.Webhooks
  alias Hive.Repo

  def create(conn, %{"project_id" => project_id, "source" => source, "token" => token}) do
    with {:ok, source_atom} <- parse_source(source),
         {:ok, project} <- fetch_project(project_id),
         %Webhook{} = webhook <- Webhooks.find_by_token(project.id, source_atom, token),
         {:ok, _alerts} <- ingest(source_atom, project, webhook, conn.body_params) do
      Webhooks.touch_last_used(webhook)
      send_resp(conn, :accepted, "")
    else
      {:error, :invalid_payload} -> send_resp(conn, :unprocessable_entity, "")
      {:error, :not_found} -> send_resp(conn, :not_found, "")
      _ -> send_resp(conn, :unauthorized, "")
    end
  end

  defp parse_source(source) when is_binary(source) do
    case Enum.find(Webhook.sources(), &(Atom.to_string(&1) == source)) do
      nil -> {:error, :unknown_source}
      atom -> {:ok, atom}
    end
  end

  defp fetch_project(id) do
    case Repo.get(Project, id) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  defp ingest(source, project, webhook, payload),
    do: Projects.ingest_webhook(source, project, webhook, payload)
end
