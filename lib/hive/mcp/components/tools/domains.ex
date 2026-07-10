defmodule Hive.MCP.Components.Tools.Domains do
  @moduledoc false

  alias Hive.MCP.Components.Tools.Projects, as: ProjectTool
  alias Hive.Repo

  def domain_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "visibility" => %{"type" => "string"},
        "projects" => %{"type" => "array", "items" => project_summary_schema()},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "name",
        "description",
        "visibility",
        "projects",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  defp project_summary_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "visibility" => %{"type" => "string"},
        "repositories" => %{"type" => "array", "items" => ProjectTool.repository_schema()}
      },
      "required" => ["id", "name", "description", "visibility", "repositories"],
      "additionalProperties" => false
    }
  end

  def domain_json(domain) do
    domain = Repo.preload(domain, projects: :github_repositories)

    %{
      id: domain.id,
      name: domain.name,
      description: domain.description,
      visibility: Atom.to_string(domain.visibility),
      projects:
        domain
        |> assoc(:projects)
        |> Enum.map(&project_json/1),
      inserted_at: iso8601(domain.inserted_at),
      updated_at: iso8601(domain.updated_at)
    }
  end

  defp project_json(project) do
    %{
      id: project.id,
      name: project.name,
      description: project.description,
      visibility: Atom.to_string(project.visibility),
      repositories:
        project
        |> assoc(:github_repositories)
        |> Enum.map(&ProjectTool.repository_json/1)
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
