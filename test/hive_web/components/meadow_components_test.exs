defmodule HiveWeb.MeadowComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Hive.GitHub.Repositories
  alias Hive.Meadows
  alias Hive.Meadows.GitHubRepository
  alias Hive.Meadows.Meadow
  alias HiveWeb.MeadowComponents

  describe "meadows/1" do
    defp assigns(overrides \\ %{}) do
      Map.merge(
        %{
          form: to_form(Meadows.change_meadow(), as: :meadow),
          meadows: [],
          repository_options: [],
          repository_load_error: nil,
          selected_repository: nil
        },
        overrides
      )
    end

    test "renders the empty state and add meadow action when editable" do
      assigns = assigns()

      html =
        rendered_to_string(~H"""
        <MeadowComponents.meadows
          meadows={@meadows}
          editable?
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
        />
        """)

      assert html =~ "Add meadow"
      assert html =~ "No meadows yet"
      assert html =~ ~s(class="noora-card")
      assert html =~ ~s(id="meadows-table")
      assert html =~ ~s(id="new-meadow-modal")
    end

    test "hides edit controls when not editable" do
      assigns = assigns()

      html =
        rendered_to_string(~H"""
        <MeadowComponents.meadows
          meadows={@meadows}
          editable?={false}
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
        />
        """)

      refute html =~ "Add meadow"
      refute html =~ ~s(id="new-meadow-modal")
      assert html =~ "Organization members will populate this list."
    end

    test "renders the new meadow modal with repository options" do
      assigns =
        assigns(%{
          repository_options: [
            %Repositories{owner: "tuist", name: "sdk", description: "Tuist SDK for Apple apps"},
            %Repositories{owner: "tuist", name: "Grafana", description: "Monitoring dashboards"},
            %Repositories{owner: "tuist", name: "AXe", description: "Simulator accessibility"}
          ],
          selected_repository: nil
        })

      html =
        rendered_to_string(~H"""
        <MeadowComponents.meadows
          meadows={@meadows}
          editable?
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
        />
        """)

      assert html =~ ~s(id="new-meadow-modal")
      assert html =~ "New meadow"
      assert html =~ "Visibility"
      assert html =~ "GitHub repository"
      assert html =~ "tuist/AXe"
      assert html =~ "tuist/Grafana"
      assert html =~ "tuist/sdk"
      assert repository_position(html, "tuist/AXe") < repository_position(html, "tuist/Grafana")
      assert repository_position(html, "tuist/Grafana") < repository_position(html, "tuist/sdk")
      assert html =~ ~s(data-label="tuist/Grafana Monitoring dashboards")
      assert html =~ ~s(class="noora-dropdown")
      assert html =~ ~s(id="new-meadow-visibility")
      assert html =~ ~s(name="meadow[visibility]")
      assert html =~ ~s(name="meadow[github_repository_owner]")
      assert html =~ ~s(name="meadow[github_repository_name]")
      assert html =~ ~s(phx-submit="save")
    end

    test "renders configured meadows and repositories" do
      meadow = %Meadow{
        id: "017b7c7d-6f1b-4c71-b0e2-cdf6f65fd3d6",
        name: "Hive",
        description: "Meadow orchestration",
        github_repositories: [%GitHubRepository{owner: "tuist", name: "hive"}]
      }

      assigns = assigns(%{meadows: [meadow]})

      html =
        rendered_to_string(~H"""
        <MeadowComponents.meadows
          meadows={@meadows}
          editable?
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
        />
        """)

      assert html =~ "Hive"
      assert html =~ "Meadow orchestration"
      assert html =~ "Public"
      assert html =~ "tuist/hive"
      assert html =~ ~s(href="/meadows/#{meadow.id}")
      assert html =~ ~s(data-type="badge")
      assert html =~ ~s(data-part="repository-cell")
    end

    test "renders a meadow detail form when editable" do
      meadow = %Meadow{
        id: "017b7c7d-6f1b-4c71-b0e2-cdf6f65fd3d6",
        name: "Atlas",
        description: "Internal planning.",
        visibility: :private,
        github_repositories: []
      }

      assigns =
        assigns(%{
          meadow: meadow,
          form: to_form(Meadows.change_meadow(meadow), as: :meadow)
        })

      html =
        rendered_to_string(~H"""
        <MeadowComponents.meadow_detail
          meadow={@meadow}
          editable?
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
          webhooks={[]}
          webhook_form={to_form(%{"name" => "", "source" => "grafana"}, as: :webhook)}
          webhook_sources={[:grafana]}
          selected_source={:grafana}
        />
        """)

      assert html =~ "Atlas"
      assert html =~ "Internal planning."
      assert html =~ "Save meadow"
      assert html =~ ~s(class="noora-dropdown")
      assert html =~ ~s(id="meadow-visibility")
      assert html =~ ~s(name="meadow[visibility]")
      assert html =~ "Webhooks"
      refute html =~ "Linked specs"
      refute html =~ "Back"
    end

    test "renders a read-only meadow detail when not editable" do
      meadow = %Meadow{
        id: "017b7c7d-6f1b-4c71-b0e2-cdf6f65fd3d6",
        name: "Atlas",
        description: "Public planning.",
        visibility: :public,
        github_repositories: []
      }

      assigns =
        assigns(%{
          meadow: meadow,
          form: to_form(Meadows.change_meadow(meadow), as: :meadow)
        })

      html =
        rendered_to_string(~H"""
        <MeadowComponents.meadow_detail
          meadow={@meadow}
          editable?={false}
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
          webhooks={[]}
          webhook_form={to_form(%{"name" => "", "source" => "grafana"}, as: :webhook)}
          webhook_sources={[:grafana]}
          selected_source={:grafana}
        />
        """)

      assert html =~ "Atlas"
      assert html =~ "Public planning."
      refute html =~ "Save meadow"
      refute html =~ "Webhooks"
      refute html =~ ~s(phx-submit="save")
    end
  end

  defp repository_position(html, repository) do
    {position, _length} = :binary.match(html, repository)
    position
  end
end
