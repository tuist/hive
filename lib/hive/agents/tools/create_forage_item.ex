defmodule Hive.Agents.Tools.CreateForageItem do
  @moduledoc false

  use Condukt.Tool

  alias Hive.Forage.Intake

  @impl true
  def name, do: "create_forage_item"

  @impl true
  def description do
    """
    Create a Hive forage item when a Slack thread explicitly asks Hive to
    capture a feature request, bug report, or feedback item. The instance
    decides whether the item is stored in Hive or published to an
    external destination such as a GitHub issue.
    """
  end

  @impl true
  def parameters do
    %{
      type: "object",
      required: ["title", "description"],
      properties: %{
        type: %{
          type: "string",
          enum: ["feature_request", "bug_report", "feedback"],
          description: "The kind of forage item to create. Defaults to feature_request."
        },
        title: %{type: "string", minLength: 1, maxLength: 160},
        description: %{type: "string", minLength: 10, maxLength: 2_000},
        source_url: %{
          type: "string",
          description: "Optional source URL that explains where the request came from."
        }
      }
    }
  end

  @impl true
  def call(args, _context) when is_map(args) do
    case Intake.current_requester() do
      nil ->
        {:error, "The Slack user is not linked to a Hive user."}

      user ->
        args
        |> Map.put_new("type", "feature_request")
        |> Intake.create(user, interface: "worker")
        |> tool_result()
    end
  end

  def call(_args, _context), do: {:error, "Provide a forage item title and description."}

  defp tool_result({:ok, result}) do
    {:ok,
     %{
       destination: Atom.to_string(result.destination),
       hive_url: result.hive_path,
       external_url: result.external_url,
       external_label: result.external_label,
       title: result.target_label
     }}
  end

  defp tool_result({:error, %Ecto.Changeset{}}) do
    {:error, "The forage item was invalid. Check the title and description length."}
  end

  defp tool_result({:error, :unauthorized}),
    do: {:error, "The Slack user is not allowed to create that forage item."}

  defp tool_result({:error, reason})
       when reason in [:github_repository_not_configured, :github_repository_not_found] do
    {:error, "The forage intake destination is not configured."}
  end

  defp tool_result({:error, _reason}), do: {:error, "The forage item could not be created."}
end
