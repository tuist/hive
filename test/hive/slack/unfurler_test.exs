defmodule Hive.Slack.UnfurlerTest do
  use Hive.DataCase, async: true

  alias Hive.Domains
  alias Hive.Drops.WeeklyDigest
  alias Hive.Forage
  alias Hive.Forage.FeatureRequest
  alias Hive.Projects
  alias Hive.Slack.Unfurler
  alias Hive.Specs

  defp app_url(path), do: HiveWeb.Endpoint.url() <> path

  defp user! do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: "alice-#{suffix}@example.com",
        provider: "test",
        provider_uid: "alice-#{suffix}@example.com"
      })

    user
  end

  defp spec!(attrs \\ %{}) do
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
        user!()
      )

    spec
  end

  defp create_project! do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    project
  end

  defp block_texts(%{"blocks" => blocks}) do
    Enum.flat_map(blocks, fn block ->
      [
        get_in(block, ["text", "text"])
        | block
          |> Map.get("fields", [])
          |> Enum.map(& &1["text"])
      ] ++
        (block
         |> Map.get("elements", [])
         |> Enum.flat_map(fn
           %{"text" => %{"text" => text}} -> [text]
           %{"text" => text} when is_binary(text) -> [text]
           _element -> []
         end))
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp button_url(%{"blocks" => blocks}) do
    blocks
    |> Enum.flat_map(&Map.get(&1, "elements", []))
    |> Enum.find(&(&1["type"] == "button"))
    |> Map.fetch!("url")
  end

  test "skips URLs whose host doesn't match the configured endpoint" do
    assert Unfurler.unfurl("https://example.org/specs/1") == :skip
  end

  test "skips malformed URLs" do
    assert Unfurler.unfurl("not a url") == :skip
    assert Unfurler.unfurl("") == :skip
  end

  test "skips Hive-hosted URLs that no dashboard route handles" do
    assert Unfurler.unfurl(app_url("/account/slack")) == :skip
  end

  test "builds Block Kit from static route OpenGraph metadata" do
    assert {:ok, payload} = Unfurler.unfurl(app_url("/ops/slack"))

    assert block_texts(payload) |> Enum.any?(&(&1 =~ "Slack"))
    assert block_texts(payload) |> Enum.any?(&(&1 =~ "Hive"))
    assert button_url(payload) == app_url("/ops/slack")
  end

  test "delegates spec detail links to the owning route" do
    spec = spec!()
    assert {:ok, payload} = Unfurler.unfurl(app_url("/specs/#{spec.number}"))

    assert block_texts(payload) |> Enum.any?(&(&1 == "Slack unfurling"))
    assert block_texts(payload) |> Enum.any?(&(&1 == "Render Hive links inline."))
    assert block_texts(payload) |> Enum.any?(&(&1 =~ "Spec ##{spec.number}"))
    assert button_url(payload) == app_url("/specs/#{spec.number}")
  end

  test "skips specs with a private visibility override" do
    spec = spec!(%{"visibility_override" => "private"})

    assert Unfurler.unfurl(app_url("/specs/#{spec.number}")) == :skip
  end

  test "skips specs that inherit private project visibility" do
    {:ok, project} =
      Projects.create_project(%{
        name: "Private project #{System.unique_integer([:positive])}",
        visibility: :private
      })

    spec = spec!(%{"project_id" => project.id, "visibility" => "public"})

    assert Unfurler.unfurl(app_url("/specs/#{spec.number}")) == :skip
  end

  test "skips specs that do not exist" do
    assert Unfurler.unfurl(app_url("/specs/9999999")) == :skip
  end

  test "delegates domain detail links to the owning route" do
    {:ok, domain} =
      Domains.create_domain(%{
        name: "Forage",
        project_id: create_project!().id,
        description: "Idea harvest.",
        visibility: :public
      })

    assert {:ok, payload} = Unfurler.unfurl(app_url("/domains/#{domain.id}"))

    assert block_texts(payload) |> Enum.any?(&(&1 == "Forage"))
    assert block_texts(payload) |> Enum.any?(&(&1 == "Idea harvest."))
    assert block_texts(payload) |> Enum.any?(&(&1 =~ "Domain"))
    assert button_url(payload) == app_url("/domains/#{domain.id}")
  end

  test "skips private domains" do
    {:ok, domain} =
      Domains.create_domain(%{
        name: "Secret",
        project_id: create_project!().id,
        visibility: :private
      })

    assert Unfurler.unfurl(app_url("/domains/#{domain.id}")) == :skip
  end

  test "delegates forage detail links to the owning route" do
    {:ok, item} =
      Forage.create_feature_request(
        %{"title" => "Slack unfurling", "description" => "Render Hive links nicely."},
        user!()
      )

    assert {:ok, payload} = Unfurler.unfurl(app_url("/forage/items/manual/#{item.id}"))

    assert block_texts(payload) |> Enum.any?(&(&1 == "Slack unfurling"))
    assert block_texts(payload) |> Enum.any?(&(&1 =~ "Feature request"))
    assert button_url(payload) == app_url("/forage/items/manual/#{item.id}")
  end

  test "skips forage items that anonymous visitors cannot see" do
    {:ok, item} =
      Repo.insert(%FeatureRequest{
        type: :feature_request,
        title: "Internal idea",
        description: "Internal only.",
        status: :open,
        visibility: :organization,
        user_id: user!().id
      })

    assert Unfurler.unfurl(app_url("/forage/items/manual/#{item.id}")) == :skip
  end

  test "unfurls a published weekly Drops digest" do
    digest = insert_drop_digest!()

    assert {:ok, payload} =
             Unfurler.unfurl(app_url("/drops/digest/#{Date.to_iso8601(digest.week_start)}"))

    assert block_texts(payload) |> Enum.any?(&(&1 == "The connected week"))
    assert block_texts(payload) |> Enum.any?(&(&1 == "The week told one story."))
    assert button_url(payload) == app_url("/drops/digest/2026-07-06")
  end

  test "skips a missing historical weekly Drops digest" do
    assert Unfurler.unfurl(app_url("/drops/digest/2025-01-06")) == :skip
  end

  defp insert_drop_digest! do
    %WeeklyDigest{}
    |> WeeklyDigest.changeset(%{
      week_start: ~D[2026-07-06],
      week_end: ~D[2026-07-10],
      status: :published,
      title: "The connected week",
      summary: "The week told one story.",
      body: "Narrated body.",
      drop_ids: [Ecto.UUID.generate()],
      published_at: ~U[2026-07-10 17:00:00Z]
    })
    |> Repo.insert!()
  end
end
