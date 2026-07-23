defmodule Hive.Agents.Tools.ListGitHubLabels do
  @moduledoc false

  use Condukt.Tool

  alias Hive.Auth
  alias Hive.Forage.Intake

  @max_labels 100
  @max_description_chars 240

  @impl true
  def name, do: "list_github_labels"

  @impl true
  def description do
    """
    List the GitHub labels available to the current Slack requester for
    forage intake. Call this only when the requester asks to create a
    forage item and matching labels would help.
    """
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{},
      additionalProperties: false
    }
  end

  @impl true
  def call(_args, context) do
    case requester_user(context) do
      nil ->
        {:error, "The Slack user is not linked to a Hive user."}

      requester ->
        if Auth.member?(requester) do
          list_labels()
        else
          {:error, "The Slack user is not allowed to list GitHub labels."}
        end
    end
  end

  defp requester_user(context) do
    context
    |> Map.get(:assigns, %{})
    |> Map.get(:requester_user)
  end

  defp list_labels do
    case Intake.available_github_labels() do
      {:ok, labels} ->
        {:ok, %{labels: labels |> Enum.map(&label_context/1) |> Enum.take(@max_labels)}}

      {:error, _reason} ->
        {:error, "The forage intake labels are unavailable."}
    end
  end

  defp label_context(label) do
    %{
      name: Map.get(label, :name) || Map.get(label, "name") || ""
    }
    |> maybe_put(:description, truncate_description(label))
  end

  defp truncate_description(label) do
    case Map.get(label, :description) || Map.get(label, "description") do
      description when is_binary(description) ->
        description |> String.trim() |> String.slice(0, @max_description_chars)

      _other ->
        nil
    end
  end

  defp maybe_put(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
