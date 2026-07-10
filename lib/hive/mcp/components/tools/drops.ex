defmodule Hive.MCP.Components.Tools.Drops do
  @moduledoc """
  Shared JSON projections for drops returned by `list_drops` and `get_drop`.
  """

  alias Hive.Drops
  alias Hive.Forage.GitHubIssue

  def drop_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "integer"},
        "number" => %{"type" => "integer"},
        "projects" => %{"type" => "array", "items" => named_reference_schema()},
        "domains" => %{"type" => "array", "items" => named_reference_schema()},
        "classified_at" => %{"type" => ["string", "null"]},
        "source_type" => %{"type" => "string"},
        "source_label" => %{"type" => "string"},
        "external_id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "body" => %{"type" => ["string", "null"]},
        "url" => %{"type" => ["string", "null"]},
        "hive_url" => %{"type" => "string"},
        "version" => %{"type" => ["string", "null"]},
        "repository" => %{"type" => ["string", "null"]},
        "github_issues" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "number" => %{"type" => "integer"},
              "title" => %{"type" => "string"},
              "state" => %{"type" => "string"},
              "url" => %{"type" => ["string", "null"]}
            },
            "required" => ["id", "number", "title", "state", "url"],
            "additionalProperties" => false
          }
        },
        "published_at" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "number",
        "projects",
        "domains",
        "classified_at",
        "source_type",
        "source_label",
        "external_id",
        "title",
        "body",
        "url",
        "hive_url",
        "version",
        "repository",
        "github_issues",
        "published_at",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  defp named_reference_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"}
      },
      "required" => ["id", "name"],
      "additionalProperties" => false
    }
  end

  def drop_json(drop) do
    domains = drop.domains || []

    %{
      id: drop.number,
      number: drop.number,
      projects:
        drop
        |> Drops.projects_for_drop()
        |> Enum.map(fn project ->
          %{id: project.id, name: project.name}
        end),
      domains:
        Enum.map(domains, fn domain ->
          %{id: domain.id, name: domain.name}
        end),
      classified_at: iso8601(drop.classified_at),
      source_type: Atom.to_string(drop.source_type),
      source_label: Drops.source_type_label(drop.source_type),
      external_id: drop.external_id,
      title: drop.title,
      body: drop.body,
      url: drop.url,
      hive_url: Drops.public_path(drop),
      version: drop.version,
      repository: repository_label(drop),
      github_issues: github_issues_json(drop),
      published_at: iso8601(drop.published_at),
      inserted_at: iso8601(drop.inserted_at),
      updated_at: iso8601(drop.updated_at)
    }
  end

  defp repository_label(%{github_repository: %{owner: owner, name: name}}),
    do: "#{owner}/#{name}"

  defp repository_label(_drop), do: nil

  defp github_issues_json(%{github_issues: %Ecto.Association.NotLoaded{}}), do: []

  defp github_issues_json(%{github_issues: issues}) when is_list(issues) do
    Enum.map(issues, fn issue ->
      %{
        id: issue.id,
        number: issue.number,
        title: issue.title,
        state: Atom.to_string(issue.state),
        url: github_issue_url(issue)
      }
    end)
  end

  defp github_issues_json(_drop), do: []

  defp github_issue_url(%GitHubIssue{github_repository: %Ecto.Association.NotLoaded{}}),
    do: nil

  defp github_issue_url(%GitHubIssue{github_repository: nil}), do: nil
  defp github_issue_url(%GitHubIssue{} = issue), do: GitHubIssue.html_url(issue)

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp iso8601(%NaiveDateTime{} = ndt),
    do: ndt |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

  defp iso8601(value), do: to_string(value)
end
