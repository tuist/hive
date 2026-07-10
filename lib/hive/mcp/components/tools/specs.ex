defmodule Hive.MCP.Components.Tools.Specs do
  @moduledoc false

  alias Hive.Specs, as: SpecContext
  alias Hive.Specs.Spec

  def spec_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "number" => %{"type" => "integer"},
        "title" => %{"type" => "string"},
        "body" => %{"type" => ["string", "null"]},
        "summary" => %{"type" => ["string", "null"]},
        "status" => %{"type" => "string"},
        "visibility" => %{"type" => "string"},
        "visibility_override" => %{"type" => ["string", "null"]},
        "effective_visibility" => %{"type" => "string"},
        "revision" => %{"type" => "integer"},
        "project" => %{
          "type" => ["object", "null"],
          "properties" => %{
            "id" => %{"type" => "string"},
            "name" => %{"type" => "string"},
            "visibility" => %{"type" => "string"}
          },
          "required" => ["id", "name", "visibility"],
          "additionalProperties" => false
        },
        "domains" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "name" => %{"type" => "string"},
              "visibility" => %{"type" => "string"}
            },
            "required" => ["id", "name", "visibility"],
            "additionalProperties" => false
          }
        },
        "source_forage_item" => %{
          "type" => ["object", "null"],
          "properties" => %{
            "type" => %{"type" => "string"},
            "id" => %{"type" => "string"},
            "title" => %{"type" => "string"}
          },
          "required" => ["type", "id", "title"],
          "additionalProperties" => false
        },
        "comments" => %{"type" => "array", "items" => comment_schema()},
        "revisions" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "revision" => %{"type" => "integer"},
              "title" => %{"type" => "string"},
              "body" => %{"type" => ["string", "null"]},
              "status" => %{"type" => "string"},
              "author" => %{"type" => ["string", "null"]},
              "inserted_at" => %{"type" => "string"}
            },
            "required" => ["revision", "title", "body", "status", "author", "inserted_at"],
            "additionalProperties" => false
          }
        },
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "number",
        "title",
        "body",
        "summary",
        "status",
        "visibility",
        "visibility_override",
        "effective_visibility",
        "revision",
        "project",
        "domains",
        "source_forage_item",
        "comments",
        "revisions",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def comment_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "author" => %{"type" => "string"},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => ["id", "body", "author", "inserted_at", "updated_at"],
      "additionalProperties" => false
    }
  end

  def spec_json(%Spec{} = spec) do
    %{
      id: spec.id,
      number: spec.number,
      title: spec.title,
      body: spec.body,
      summary: spec.summary,
      status: Atom.to_string(spec.status),
      visibility: Atom.to_string(SpecContext.effective_visibility(spec)),
      visibility_override: visibility_override(spec),
      effective_visibility: Atom.to_string(SpecContext.effective_visibility(spec)),
      revision: spec.lock_version,
      project: project_json(spec),
      domains:
        Enum.map((Ecto.assoc_loaded?(spec.domains) && spec.domains) || [], fn domain ->
          %{
            id: domain.id,
            name: domain.name,
            visibility: Atom.to_string(domain.visibility)
          }
        end),
      source_forage_item:
        if spec.source_feature_request do
          %{
            type: "feature_request",
            id: spec.source_feature_request.id,
            title: spec.source_feature_request.title
          }
        end,
      comments: comments_json(spec),
      revisions:
        Enum.map(
          (Ecto.assoc_loaded?(spec.revisions) && spec.revisions) || [],
          &revision_json/1
        ),
      inserted_at: spec.inserted_at,
      updated_at: spec.updated_at
    }
  end

  def comments_json(%Spec{} = spec) do
    Enum.map((Ecto.assoc_loaded?(spec.comments) && spec.comments) || [], &comment_json/1)
  end

  defp visibility_override(%{visibility_override: nil}), do: nil
  defp visibility_override(%{visibility_override: override}), do: Atom.to_string(override)

  defp project_json(%{project: project}) do
    if Ecto.assoc_loaded?(project) and not is_nil(project) do
      %{
        id: project.id,
        name: project.name,
        visibility: Atom.to_string(project.visibility)
      }
    end
  end

  defp comment_json(comment) do
    %{
      id: comment.id,
      body: comment.body,
      author: comment_author(comment),
      inserted_at: comment.inserted_at,
      updated_at: comment.updated_at
    }
  end

  defp comment_author(%{user: %{email: email}}) when is_binary(email), do: email
  defp comment_author(%{author_name: name}) when is_binary(name), do: name
  defp comment_author(_comment), do: "Anonymous"

  defp revision_json(revision) do
    %{
      revision: revision.revision,
      title: revision.title,
      body: revision.body,
      status: Atom.to_string(revision.status),
      author: revision_author(revision),
      inserted_at: revision.inserted_at
    }
  end

  defp revision_author(%{user: %{email: email}}) when is_binary(email), do: email
  defp revision_author(_revision), do: nil
end
