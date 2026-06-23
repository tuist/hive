defmodule Hive.Domains.SlackUnfurlTest do
  use Hive.DataCase, async: true

  alias Hive.Domains
  alias Hive.Domains.SlackUnfurl
  alias Hive.Projects

  defp uri(path), do: URI.parse("http://localhost" <> path)

  test "unfurl/1 returns a payload for a public domain" do
    {:ok, domain} =
      Domains.create_domain(%{
        name: "Forage",
        project_id: create_project!().id,
        description: "Idea harvest.",
        visibility: :public
      })

    assert {:ok, payload} = SlackUnfurl.unfurl(uri("/domains/#{domain.id}"))
    assert payload["title"] == "Forage"
    assert payload["title_link"] == "http://localhost/domains/#{domain.id}"
    assert payload["text"] == "Idea harvest."
    assert payload["footer"] == "Hive · domain"
  end

  test "unfurl/1 skips private domains" do
    {:ok, domain} =
      Domains.create_domain(%{
        name: "Secret",
        project_id: create_project!().id,
        visibility: :private
      })

    assert SlackUnfurl.unfurl(uri("/domains/#{domain.id}")) == :skip
  end

  test "unfurl/1 skips domains that don't exist" do
    assert SlackUnfurl.unfurl(uri("/domains/#{Ecto.UUID.generate()}")) == :skip
  end

  test "unfurl/1 skips when the path is not a domain URL" do
    assert SlackUnfurl.unfurl(uri("/specs/1")) == :skip
    assert SlackUnfurl.unfurl(uri("/domains/not-a-uuid")) == :skip
  end

  defp create_project! do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    project
  end
end
