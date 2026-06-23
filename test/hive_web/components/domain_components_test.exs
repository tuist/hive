defmodule HiveWeb.DomainComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Hive.Domains
  alias Hive.Domains.Domain
  alias Hive.Projects.Project
  alias HiveWeb.DomainComponents

  defp project_with(name \\ "Hive"),
    do: %Project{
      id: "00000000-0000-0000-0000-000000000001",
      name: name
    }

  describe "domains/1" do
    defp assigns(overrides \\ %{}) do
      Map.merge(
        %{
          form: to_form(Domains.change_domain(), as: :domain),
          domains: [],
          projects: [project_with()]
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
        projects: [project_with()]
      }

      assigns = assigns(%{domains: [domain]})

      html =
        rendered_to_string(~H"""
        <DomainComponents.domains
          domains={@domains}
          editable?={false}
          form={@form}
        />
        """)

      refute html =~ "Add domain"
      refute html =~ ~s(id="new-domain-modal")
      refute html =~ ~s(href="/domains/#{domain.id}")
    end

    test "renders the new domain modal as a reusable taxonomy form" do
      assigns = assigns()

      html =
        rendered_to_string(~H"""
        <DomainComponents.domains
          domains={@domains}
          editable?
          form={@form}
        />
        """)

      assert html =~ ~s(id="new-domain-modal")
      assert html =~ "New domain"
      assert html =~ "Create a reusable domain the team can link to projects."
      assert html =~ "Name"
      assert html =~ "Description"
      refute html =~ "Visibility"
      refute html =~ "GitHub repository"
      refute html =~ ~s(id="new-domain-visibility")
      refute html =~ ~s(id="new-domain-project")
      refute html =~ ~s(name="domain[project_id]")
      refute html =~ ~s(name="domain[visibility]")
      refute html =~ ~s(name="domain[github_repository_owner]")
      refute html =~ ~s(name="domain[github_repository_name]")
      assert html =~ ~s(phx-submit="save")
    end

    test "renders configured domains and projects" do
      domain = %Domain{
        id: "017b7c7d-6f1b-4c71-b0e2-cdf6f65fd3d6",
        name: "Hive",
        description: "Domain orchestration",
        projects: [project_with("Product")]
      }

      assigns = assigns(%{domains: [domain]})

      html =
        rendered_to_string(~H"""
        <DomainComponents.domains
          domains={@domains}
          editable?
          form={@form}
        />
        """)

      assert html =~ "Hive"
      assert html =~ "Domain orchestration"
      assert html =~ "Product"
      assert html =~ ~s(href="/domains/#{domain.id}")
      assert html =~ ~s(data-type="badge")
      assert html =~ ~s(data-part="project-cell")
    end

    test "renders a domain detail form when editable" do
      domain = %Domain{
        id: "017b7c7d-6f1b-4c71-b0e2-cdf6f65fd3d6",
        name: "Atlas",
        description: "Internal planning.",
        visibility: :private,
        projects: [project_with()]
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
          delete_domain_form={to_form(%{"name" => ""})}
        />
        """)

      assert html =~ "Atlas"
      assert html =~ "Internal planning."
      assert html =~ "Save domain"
      assert html =~ "Delete domain"
      refute html =~ ~s(id="domain-visibility")
      refute html =~ ~s(name="domain[visibility]")
      refute html =~ "GitHub repository"
      refute html =~ ~s(name="domain[github_repository_owner]")
      refute html =~ ~s(name="domain[github_repository_name]")
      refute html =~ "Webhooks"
      refute html =~ "Linked specs"
      refute html =~ "Back"
    end

    test "renders a read-only domain detail when not editable" do
      domain = %Domain{
        id: "017b7c7d-6f1b-4c71-b0e2-cdf6f65fd3d6",
        name: "Atlas",
        description: "Public planning.",
        visibility: :public,
        projects: [project_with()]
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
        />
        """)

      assert html =~ "Atlas"
      assert html =~ "Public planning."
      refute html =~ "Save domain"
      refute html =~ "Webhooks"
      refute html =~ ~s(phx-submit="save")
    end
  end
end
