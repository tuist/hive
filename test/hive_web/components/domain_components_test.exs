defmodule HiveWeb.DomainComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Hive.GitHub.Repositories
  alias Hive.Domains
  alias Hive.Domains.GitHubRepository
  alias Hive.Domains.Domain
  alias Hive.Projects.Project
  alias HiveWeb.DomainComponents

  defp project_with(repos),
    do: %Project{
      id: "00000000-0000-0000-0000-000000000001",
      name: "Hive",
      github_repositories: repos
    }

  describe "domains/1" do
    defp assigns(overrides \\ %{}) do
      Map.merge(
        %{
          form: to_form(Domains.change_domain(), as: :domain),
          domains: [],
          repository_options: [],
          repository_load_error: nil,
          selected_repository: nil
        },
        overrides
      )
    end

    test "renders the empty state and add domain action when editable" do
      assigns = assigns()

      html =
        rendered_to_string(~H"""
        <DomainComponents.domains
          domains={@domains}
          editable?
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
        />
        """)

      assert html =~ "Add domain"
      assert html =~ "No domains yet"
      assert html =~ ~s(class="noora-card")
      assert html =~ ~s(id="domains-table")
      assert html =~ ~s(id="new-domain-modal")
    end

    test "hides edit controls and row navigation when not editable" do
      domain = %Domain{
        id: "017b7c7d-6f1b-4c71-b0e2-cdf6f65fd3d6",
        name: "Hive",
        project: project_with([])
      }

      assigns = assigns(%{domains: [domain]})

      html =
        rendered_to_string(~H"""
        <DomainComponents.domains
          domains={@domains}
          editable?={false}
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
        />
        """)

      refute html =~ "Add domain"
      refute html =~ ~s(id="new-domain-modal")
      refute html =~ ~s(href="/domains/#{domain.id}")
    end

    test "renders the new domain modal with repository options" do
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
        <DomainComponents.domains
          domains={@domains}
          editable?
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
        />
        """)

      assert html =~ ~s(id="new-domain-modal")
      assert html =~ "New domain"
      assert html =~ "Visibility"
      assert html =~ "GitHub repository"
      assert html =~ "tuist/AXe"
      assert html =~ "tuist/Grafana"
      assert html =~ "tuist/sdk"
      assert repository_position(html, "tuist/AXe") < repository_position(html, "tuist/Grafana")
      assert repository_position(html, "tuist/Grafana") < repository_position(html, "tuist/sdk")
      assert html =~ ~s(data-label="tuist/Grafana Monitoring dashboards")
      assert html =~ ~s(class="noora-dropdown")
      assert html =~ ~s(id="new-domain-visibility")
      assert html =~ ~s(name="domain[visibility]")
      assert html =~ ~s(name="domain[github_repository_owner]")
      assert html =~ ~s(name="domain[github_repository_name]")
      assert html =~ ~s(phx-submit="save")
    end

    test "renders configured domains and repositories" do
      domain = %Domain{
        id: "017b7c7d-6f1b-4c71-b0e2-cdf6f65fd3d6",
        name: "Hive",
        description: "Domain orchestration",
        project: project_with([%GitHubRepository{owner: "tuist", name: "hive"}])
      }

      assigns = assigns(%{domains: [domain]})

      html =
        rendered_to_string(~H"""
        <DomainComponents.domains
          domains={@domains}
          editable?
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
        />
        """)

      assert html =~ "Hive"
      assert html =~ "Domain orchestration"
      assert html =~ "Public"
      assert html =~ "tuist/hive"
      assert html =~ ~s(href="/domains/#{domain.id}")
      assert html =~ ~s(data-type="badge")
      assert html =~ ~s(data-part="repository-cell")
    end

    test "renders a domain detail form when editable" do
      domain = %Domain{
        id: "017b7c7d-6f1b-4c71-b0e2-cdf6f65fd3d6",
        name: "Atlas",
        description: "Internal planning.",
        visibility: :private,
        project: project_with([])
      }

      assigns =
        assigns(%{
          domain: domain,
          form: to_form(Domains.change_domain(domain), as: :domain)
        })

      html =
        rendered_to_string(~H"""
        <DomainComponents.domain_detail
          domain={@domain}
          editable?
          form={@form}
          repository_options={@repository_options}
          repository_load_error={@repository_load_error}
          selected_repository={@selected_repository}
          webhooks={[]}
          webhook_form={to_form(%{"name" => "", "source" => "grafana"}, as: :webhook)}
          webhook_sources={[:grafana]}
          selected_source={:grafana}
          delete_domain_form={to_form(%{"name" => ""})}
        />
        """)

      assert html =~ "Atlas"
      assert html =~ "Internal planning."
      assert html =~ "Save domain"
      assert html =~ "Delete domain"
      assert html =~ ~s(class="noora-dropdown")
      assert html =~ ~s(id="domain-visibility")
      assert html =~ ~s(name="domain[visibility]")
      assert html =~ "Webhooks"
      refute html =~ "Linked specs"
      refute html =~ "Back"
    end

    test "renders a read-only domain detail when not editable" do
      domain = %Domain{
        id: "017b7c7d-6f1b-4c71-b0e2-cdf6f65fd3d6",
        name: "Atlas",
        description: "Public planning.",
        visibility: :public,
        project: project_with([])
      }

      assigns =
        assigns(%{
          domain: domain,
          form: to_form(Domains.change_domain(domain), as: :domain)
        })

      html =
        rendered_to_string(~H"""
        <DomainComponents.domain_detail
          domain={@domain}
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
      refute html =~ "Save domain"
      refute html =~ "Webhooks"
      refute html =~ ~s(phx-submit="save")
    end
  end

  defp repository_position(html, repository) do
    {position, _length} = :binary.match(html, repository)
    position
  end
end
