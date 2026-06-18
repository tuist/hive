defmodule Hive.Specs.SlackUnfurl do
  @moduledoc """
  Turns `/specs/:number` URLs into Slack unfurls.

  Skips specs whose effective visibility is `:private` so an internal
  proposal isn't leaked to the workspace.
  """

  @behaviour Hive.Slack.Unfurl

  alias Hive.Specs
  alias Hive.Specs.Spec

  @impl true
  def unfurl(%URI{path: path} = uri) when is_binary(path) do
    case Path.split(path) do
      ["/", "specs", number] -> unfurl_spec(number, uri)
      _ -> :skip
    end
  end

  def unfurl(_uri), do: :skip

  defp unfurl_spec(number, uri) do
    with {number, ""} <- Integer.parse(number),
         %Spec{} = spec <- safe_get_by_number(number),
         :public <- Specs.effective_visibility(spec) do
      {:ok, payload(spec, uri)}
    else
      _ -> :skip
    end
  end

  defp safe_get_by_number(number) do
    Specs.get_spec_by_number!(number)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp payload(%Spec{} = spec, uri) do
    %{
      "title" => "Spec ##{spec.number}: #{spec.title}",
      "title_link" => URI.to_string(uri),
      "text" => spec.summary || excerpt(spec.body),
      "footer" => "Hive · spec · #{spec.status}"
    }
  end

  defp excerpt(nil), do: nil

  defp excerpt(body) when is_binary(body) do
    body
    |> String.split(~r/\n+/, parts: 2)
    |> List.first()
    |> String.slice(0, 280)
  end
end
