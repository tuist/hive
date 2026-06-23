defmodule Hive.MCP.Components.Tools.Projects do
  @moduledoc false

  alias Hive.Domains.GitHubRepository
  alias Hive.Projects.Webhook
  alias Hive.Repo

  def project_json(project) do
    project = Repo.preload(project, [:domains, :github_repositories, :webhooks])

    %{
      id: project.id,
      name: project.name,
      description: project.description,
      visibility: Atom.to_string(project.visibility),
      domains:
        project
        |> assoc(:domains)
        |> Enum.map(&domain_json/1),
      repositories:
        project
        |> assoc(:github_repositories)
        |> Enum.map(&repository_json/1),
      webhooks:
        project
        |> assoc(:webhooks)
        |> Enum.map(&webhook_json/1),
      inserted_at: iso8601(project.inserted_at),
      updated_at: iso8601(project.updated_at)
    }
  end

  def repository_json(%GitHubRepository{} = repository) do
    %{
      id: repository.id,
      owner: repository.owner,
      name: repository.name,
      full_name: GitHubRepository.full_name(repository),
      visibility: Atom.to_string(repository.visibility),
      inserted_at: iso8601(repository.inserted_at),
      updated_at: iso8601(repository.updated_at)
    }
  end

  def webhook_json(%Webhook{} = webhook) do
    %{
      id: webhook.id,
      name: webhook.name,
      source: Atom.to_string(webhook.source),
      source_label: Webhook.source_label(webhook.source),
      last_used_at: iso8601(webhook.last_used_at),
      inserted_at: iso8601(webhook.inserted_at),
      updated_at: iso8601(webhook.updated_at)
    }
  end

  defp domain_json(domain) do
    %{
      id: domain.id,
      name: domain.name,
      description: domain.description,
      visibility: Atom.to_string(domain.visibility)
    }
  end

  defp assoc(resource, key) do
    value = Map.get(resource, key)
    if Ecto.assoc_loaded?(value), do: value, else: []
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp iso8601(%NaiveDateTime{} = value),
    do: value |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()
end
