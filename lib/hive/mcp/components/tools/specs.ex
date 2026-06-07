defmodule Hive.MCP.Components.Tools.Specs do
  @moduledoc false

  alias Hive.Specs.Spec

  def spec_json(%Spec{} = spec) do
    %{
      id: spec.id,
      title: spec.title,
      body: spec.body,
      status: Atom.to_string(spec.status),
      revision: spec.lock_version,
      source_forage_item:
        if spec.source_feature_request do
          %{
            type: "feature_request",
            id: spec.source_feature_request.id,
            title: spec.source_feature_request.title
          }
        end,
      comments:
        Enum.map((Ecto.assoc_loaded?(spec.comments) && spec.comments) || [], &comment_json/1),
      revisions:
        Enum.map(
          (Ecto.assoc_loaded?(spec.revisions) && spec.revisions) || [],
          &revision_json/1
        ),
      inserted_at: spec.inserted_at,
      updated_at: spec.updated_at
    }
  end

  defp comment_json(comment) do
    %{
      id: comment.id,
      body: comment.body,
      author: comment_author(comment),
      inserted_at: comment.inserted_at
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
