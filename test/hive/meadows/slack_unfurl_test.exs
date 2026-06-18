defmodule Hive.Meadows.SlackUnfurlTest do
  use Hive.DataCase, async: true

  alias Hive.Meadows
  alias Hive.Meadows.SlackUnfurl

  defp uri(path), do: URI.parse("http://localhost" <> path)

  test "unfurl/1 returns a payload for a public meadow" do
    {:ok, meadow} =
      Meadows.create_meadow(%{name: "Forage", description: "Idea harvest.", visibility: :public})

    assert {:ok, payload} = SlackUnfurl.unfurl(uri("/meadows/#{meadow.id}"))
    assert payload["title"] == "Forage"
    assert payload["title_link"] == "http://localhost/meadows/#{meadow.id}"
    assert payload["text"] == "Idea harvest."
    assert payload["footer"] == "Hive · meadow"
  end

  test "unfurl/1 skips private meadows" do
    {:ok, meadow} = Meadows.create_meadow(%{name: "Secret", visibility: :private})

    assert SlackUnfurl.unfurl(uri("/meadows/#{meadow.id}")) == :skip
  end

  test "unfurl/1 skips meadows that don't exist" do
    assert SlackUnfurl.unfurl(uri("/meadows/#{Ecto.UUID.generate()}")) == :skip
  end

  test "unfurl/1 skips when the path is not a meadow URL" do
    assert SlackUnfurl.unfurl(uri("/specs/1")) == :skip
    assert SlackUnfurl.unfurl(uri("/meadows/not-a-uuid")) == :skip
  end
end
