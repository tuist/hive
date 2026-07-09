defmodule Hive.Specs.SlackUnfurlTest do
  use Hive.DataCase, async: true

  alias Hive.Specs
  alias Hive.Specs.SlackUnfurl

  defp user! do
    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "alice-#{System.unique_integer([:positive])}@example.com",
        provider: "test",
        provider_uid: "alice-#{System.unique_integer([:positive])}@example.com"
      })

    user
  end

  defp spec!(attrs \\ %{}) do
    user = user!()

    {:ok, spec} =
      Specs.create_spec(
        Map.merge(
          %{
            "title" => "Slack unfurling",
            "body" => "Hive should unfurl links.",
            "summary" => "Render Hive links inline."
          },
          attrs
        ),
        user
      )

    spec
  end

  defp uri(path), do: URI.parse("http://localhost" <> path)

  test "unfurl/1 returns a payload for a public spec" do
    spec = spec!()

    assert {:ok, payload} = SlackUnfurl.unfurl(uri("/specs/#{spec.number}"))
    assert payload["title"] == "Spec ##{spec.number}: Slack unfurling"
    assert payload["title_link"] == "http://localhost/specs/#{spec.number}"
    assert payload["text"] == "Render Hive links inline."
    assert payload["footer"] == "Hive · spec · draft"
  end

  test "unfurl/1 skips private specs" do
    spec = spec!(%{"visibility_override" => "private"})

    assert SlackUnfurl.unfurl(uri("/specs/#{spec.number}")) == :skip
  end

  test "unfurl/1 falls back to body excerpt when no summary is set" do
    spec =
      spec!(%{
        "title" => "No summary",
        "body" => "First line of the body\nSecond line",
        "summary" => nil
      })

    assert {:ok, payload} = SlackUnfurl.unfurl(uri("/specs/#{spec.number}"))
    assert payload["text"] == "First line of the body"
  end

  test "unfurl/1 skips when the spec does not exist" do
    assert SlackUnfurl.unfurl(uri("/specs/9999999")) == :skip
  end

  test "unfurl/1 skips when the path is not a spec URL" do
    assert SlackUnfurl.unfurl(uri("/forage/items/manual/abc")) == :skip
    assert SlackUnfurl.unfurl(uri("/specs/not-a-number")) == :skip
  end
end
