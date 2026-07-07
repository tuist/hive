defmodule HiveWeb.OpsLive.Forage do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Audit
  alias Hive.Domains.GitHubRepository
  alias Hive.Forage
  alias Hive.Forage.Intake
  alias Hive.Forage.IntakeSettings
  alias Hive.Ops.Policy
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description: dgettext("dashboard_forage", "Configure how new forage items are captured."),
      section_label: dgettext("dashboard_forage", "Ops"),
      highlights: [
        dgettext("dashboard_forage", "Hive-managed items"),
        dgettext("dashboard_forage", "GitHub issue intake"),
        dgettext("dashboard_forage", "Shared Slack and Model Context Protocol behavior")
      ],
      id: "ops-forage",
      path: "/ops/forage",
      title: dgettext("dashboard_forage", "Forage")
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard_forage", "Log in to manage forage intake."))
         |> redirect(to: ~p"/login?return_to=/ops/forage")}

      not Policy.authorize?(:forage_intake_settings_manage, user, nil) ->
        {:ok,
         socket
         |> put_flash(
           :error,
           dgettext("dashboard_forage", "Only instance admins can manage forage intake.")
         )
         |> push_navigate(to: ~p"/")}

      true ->
        {:ok,
         socket
         |> assign(
           :page_title,
           dgettext("dashboard_forage", "Forage · %{product}",
             product: socket.assigns.product_name
           )
         )
         |> assign(OpenGraph.assigns(open_graph()))
         |> assign(:repositories, Forage.list_github_issue_repositories())
         |> assign_settings(Intake.settings())}
    end
  end

  @impl true
  def handle_event("validate", %{"forage_intake_settings" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> Intake.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_settings_form(socket, changeset)}
  end

  def handle_event("save", %{"forage_intake_settings" => params}, socket) do
    case Intake.update_settings(socket.assigns.settings, params) do
      {:ok, settings} ->
        record_settings_audit(settings)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_forage", "Forage intake updated."))
         |> assign_settings(settings)}

      {:error, changeset} ->
        {:noreply, assign_settings_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.ops
      flash={@flash}
      product_name={@product_name}
      user_name={@user_name}
      user_email={@user_email}
      avatar_color={@avatar_color}
      signed_in?={@signed_in?}
      csrf_token={@csrf_token}
      current_path={@current_path}
    >
      <section id="ops-forage">
        <div data-part="page-header">
          <div data-part="title-group">
            <h1>{dgettext("dashboard_forage", "Forage")}</h1>
            <p>
              {dgettext(
                "dashboard_forage",
                "Choose where dashboard submissions, Slack captures, agent actions, and Model Context Protocol tools create new forage items."
              )}
            </p>
          </div>
        </div>

        <.card
          icon="rss"
          title={dgettext("dashboard_forage", "Intake destination")}
          data-part="intake-card"
        >
          <.card_section data-part="settings-section">
            <.form
              id="forage-intake-settings-form"
              for={@settings_form}
              phx-change="validate"
              phx-submit="save"
              data-part="form"
            >
              <div data-part="select-field">
                <span>{dgettext("dashboard_forage", "Destination")}</span>
                <.select
                  id="forage-intake-destination"
                  name={@settings_form[:destination].name}
                  value={select_value(@settings_form, :destination)}
                  label={destination_label(select_value(@settings_form, :destination))}
                >
                  <:item
                    value="github_issue"
                    label={dgettext("dashboard_forage", "GitHub issue")}
                  />
                  <:item
                    value="hive_item"
                    label={dgettext("dashboard_forage", "Hive-managed item")}
                  />
                </.select>
              </div>

              <div
                :if={github_issue_destination?(@settings_form) and @repositories == []}
                data-part="repository-warning"
              >
                <.alert
                  status="warning"
                  size="medium"
                  title={dgettext("dashboard_forage", "No linked GitHub repositories")}
                  description={
                    dgettext(
                      "dashboard_forage",
                      "Link a repository from a project before selecting GitHub issue intake."
                    )
                  }
                />
              </div>

              <div :if={github_issue_destination?(@settings_form)} data-part="select-field">
                <span>{dgettext("dashboard_forage", "GitHub repository")}</span>
                <.select
                  id="forage-intake-github-repository"
                  name={@settings_form[:github_repository_id].name}
                  value={select_value(@settings_form, :github_repository_id)}
                  label={
                    repository_label(
                      @repositories,
                      select_value(@settings_form, :github_repository_id)
                    )
                  }
                  disabled={@repositories == []}
                >
                  <:item
                    value={IntakeSettings.empty_github_repository_id_value()}
                    label={dgettext("dashboard_forage", "Choose repository")}
                  />
                  <:item
                    :for={repository <- sorted_repositories(@repositories)}
                    value={repository.id}
                    label={GitHubRepository.full_name(repository)}
                  />
                </.select>
              </div>

              <div data-part="form-actions">
                <.button
                  label={dgettext("dashboard_forage", "Save settings")}
                  variant="primary"
                  size="medium"
                  type="submit"
                />
              </div>
            </.form>
          </.card_section>
        </.card>
      </section>
    </Layouts.ops>
    """
  end

  defp assign_settings(socket, %IntakeSettings{} = settings) do
    socket
    |> assign(:settings, settings)
    |> assign_settings_form(Intake.change_settings(settings))
  end

  defp assign_settings_form(socket, changeset) do
    assign(socket, :settings_form, to_form(changeset, as: :forage_intake_settings))
  end

  defp select_value(form, field) do
    case Phoenix.HTML.Form.normalize_value("select", form[field].value) do
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      value -> value
    end
  end

  defp github_issue_destination?(form), do: select_value(form, :destination) == "github_issue"

  defp destination_label("github_issue"), do: dgettext("dashboard_forage", "GitHub issue")

  defp destination_label(_destination),
    do: dgettext("dashboard_forage", "Hive-managed item")

  defp repository_label(_repositories, value) when value in [nil, ""] do
    dgettext("dashboard_forage", "Choose repository")
  end

  defp repository_label(repositories, value) do
    if value == IntakeSettings.empty_github_repository_id_value() do
      dgettext("dashboard_forage", "Choose repository")
    else
      repositories
      |> Enum.find(&(&1.id == value))
      |> case do
        %GitHubRepository{} = repository -> GitHubRepository.full_name(repository)
        nil -> dgettext("dashboard_forage", "Choose repository")
      end
    end
  end

  defp sorted_repositories(repositories) do
    Enum.sort_by(repositories, &(GitHubRepository.full_name(&1) |> String.downcase()))
  end

  defp record_settings_audit(%IntakeSettings{} = settings) do
    Audit.record(:"forage_intake_settings.updated", %{
      target_type: "forage_intake_settings",
      target_id: settings.id,
      target_label: dgettext("dashboard_forage", "Forage intake"),
      metadata: %{
        "destination" => Atom.to_string(settings.destination),
        "github_repository_id" => settings.github_repository_id,
        "path" => "/ops/forage"
      }
    })
  end
end
