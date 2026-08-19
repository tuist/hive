defmodule Hive.MCP.Components.Tools.Postmortems do
  @moduledoc false

  alias Hive.Postmortems, as: PostmortemContext
  alias Hive.Postmortems.ActionItem
  alias Hive.Postmortems.Postmortem

  def postmortem_json(%Postmortem{} = postmortem) do
    %{
      id: postmortem.id,
      number: postmortem.number,
      title: PostmortemContext.title(postmortem),
      body: postmortem.body,
      visibility: Atom.to_string(postmortem.visibility),
      author: author_json(postmortem),
      domains: domains_json(postmortem),
      action_items: action_items_json(postmortem),
      inserted_at: postmortem.inserted_at,
      updated_at: postmortem.updated_at,
      path: "/postmortems/#{postmortem.number}"
    }
  end

  def action_item_json(%ActionItem{} = action_item) do
    %{
      id: action_item.id,
      postmortem_id: action_item.postmortem_id,
      title: action_item.title,
      description: action_item.description,
      resolution_url: action_item.resolution_url,
      priority: Atom.to_string(action_item.priority),
      completed: not is_nil(action_item.completed_at),
      completed_at: action_item.completed_at,
      inserted_at: action_item.inserted_at,
      updated_at: action_item.updated_at
    }
  end

  def action_items_json(%Postmortem{} = postmortem) do
    Enum.map(
      (Ecto.assoc_loaded?(postmortem.action_items) && postmortem.action_items) || [],
      &action_item_json/1
    )
  end

  defp author_json(%{created_by_user: author}) do
    if Ecto.assoc_loaded?(author) and not is_nil(author) do
      %{id: author.id, email: author.email, name: author.name}
    end
  end

  defp domains_json(%{domains: domains}) do
    Enum.map((Ecto.assoc_loaded?(domains) && domains) || [], fn domain ->
      %{id: domain.id, name: domain.name, visibility: Atom.to_string(domain.visibility)}
    end)
  end
end
