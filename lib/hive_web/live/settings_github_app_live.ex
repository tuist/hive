defmodule HiveWeb.SettingsGitHubAppLive do
  use HiveWeb, :live_view
  use Noora

  import HiveWeb.CoreComponents, only: []

  alias Hive.Integrations

  def mount(%{"id" => id}, _session, socket) do
    case Integrations.get_github_app(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("GitHub app not found."))
         |> push_navigate(to: ~p"/settings/signal-sources")}

      app ->
        repositories = Integrations.list_github_repositories(app)

        socket =
          socket
          |> assign(:page_title, app.name)
          |> assign(:app, app)
          |> assign(:repositories, repositories)
          |> assign(:show_edit_form, false)
          |> assign_app_form(app)
          |> assign_repository_form()

        {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div id="settings">
      <h1 data-part="title">{@app.name}</h1>

      <.card title={gettext("Configuration")} icon="settings" data-part="config-card">
        <.card_section data-part="app-config">
          <div :if={!@show_edit_form} data-part="bot-info">
            <div data-part="bot-details">
              <div data-part="bot-field">
                <span data-part="label">{gettext("Name")}</span>
                <span data-part="value">{@app.name}</span>
              </div>
              <div data-part="bot-field">
                <span data-part="label">{gettext("Webhook Secret")}</span>
                <span data-part="value">{mask_token(@app.webhook_secret)}</span>
              </div>
              <div data-part="bot-field">
                <span data-part="label">{gettext("Webhook URL")}</span>
                <span data-part="value">
                  {"https://#{HiveWeb.Endpoint.host()}/api/github/events"}
                </span>
              </div>
            </div>
            <div data-part="actions">
              <.button
                label={gettext("Edit")}
                variant="secondary"
                size="medium"
                phx-click="edit_app"
              />
              <.button
                label={gettext("Delete App")}
                variant="destructive"
                size="medium"
                phx-click="delete_app"
                data-confirm={
                  gettext(
                    "Are you sure? This will remove the app and all its monitored repositories."
                  )
                }
              />
            </div>
          </div>

          <.form
            :if={@show_edit_form}
            for={@app_form}
            phx-submit="update_app"
            data-part="bot-form"
          >
            <.text_input
              field={@app_form[:name]}
              type="basic"
              label={gettext("Name")}
              placeholder={gettext("e.g. My GitHub App")}
            />
            <.text_input
              field={@app_form[:webhook_secret]}
              type="basic"
              label={gettext("Webhook Secret")}
              placeholder={gettext("The secret configured in your GitHub App's webhook settings")}
            />
            <div data-part="form-actions">
              <.button label={gettext("Save")} size="medium" type="submit" />
              <.button
                label={gettext("Cancel")}
                variant="secondary"
                size="medium"
                type="button"
                phx-click="cancel_edit"
              />
            </div>
          </.form>
        </.card_section>
      </.card>

      <.card title={gettext("Monitored Repositories")} icon="bell" data-part="repositories-card">
        <.card_section data-part="monitored-repositories">
          <.form for={@repository_form} phx-submit="add_repository" data-part="repository-form">
            <div data-part="channel-inputs">
              <.text_input
                field={@repository_form[:owner]}
                type="basic"
                label={gettext("Owner")}
                placeholder={gettext("e.g. tuist")}
              />
              <.text_input
                field={@repository_form[:repo]}
                type="basic"
                label={gettext("Repository")}
                placeholder={gettext("e.g. tuist")}
              />
            </div>
            <.button label={gettext("Add Repository")} size="medium" type="submit" />
          </.form>

          <.table :if={@repositories != []} id="github-repositories" rows={@repositories}>
            <:col :let={repository} label={gettext("Repository")}>
              <.text_cell label={"#{repository.owner}/#{repository.repo}"} />
            </:col>
            <:col :let={repository} label="">
              <.button
                label={gettext("Remove")}
                variant="destructive"
                size="small"
                phx-click="remove_repository"
                phx-value-id={repository.id}
              />
            </:col>
          </.table>

          <p :if={@repositories == []} data-part="empty">
            {gettext("No repositories being monitored yet.")}
          </p>
        </.card_section>
      </.card>
    </div>
    """
  end

  def handle_event("edit_app", _params, socket) do
    {:noreply, assign(socket, :show_edit_form, true)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :show_edit_form, false)}
  end

  def handle_event("update_app", %{"github_app" => params}, socket) do
    case Integrations.update_github_app(socket.assigns.app, params) do
      {:ok, app} ->
        app = Hive.Repo.preload(app, :repositories)

        {:noreply,
         socket
         |> assign(:app, app)
         |> assign(:show_edit_form, false)
         |> assign(:page_title, app.name)
         |> assign_app_form(app)
         |> put_flash(:info, gettext("App updated."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :app_form, to_form(changeset, as: "github_app"))}
    end
  end

  def handle_event("delete_app", _params, socket) do
    case Integrations.delete_github_app(socket.assigns.app) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("GitHub app deleted."))
         |> push_navigate(to: ~p"/settings/signal-sources")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete app."))}
    end
  end

  def handle_event("add_repository", %{"github_repository" => params}, socket) do
    case Integrations.add_github_repository(socket.assigns.app, atomize_keys(params)) do
      {:ok, _repository} ->
        repositories = Integrations.list_github_repositories(socket.assigns.app)

        {:noreply,
         socket
         |> assign(:repositories, repositories)
         |> assign_repository_form()
         |> put_flash(:info, gettext("Repository added."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :repository_form, to_form(changeset, as: "github_repository"))}
    end
  end

  def handle_event("remove_repository", %{"id" => id}, socket) do
    case Integrations.delete_github_repository(id) do
      {:ok, _} ->
        repositories = Integrations.list_github_repositories(socket.assigns.app)

        {:noreply,
         socket
         |> assign(:repositories, repositories)
         |> put_flash(:info, gettext("Repository removed."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to remove repository."))}
    end
  end

  defp assign_app_form(socket, app) do
    changeset = Integrations.change_github_app(app)
    assign(socket, :app_form, to_form(changeset, as: "github_app"))
  end

  defp assign_repository_form(socket) do
    changeset =
      Hive.Integrations.GitHubRepository.changeset(%Hive.Integrations.GitHubRepository{}, %{})

    assign(socket, :repository_form, to_form(changeset, as: "github_repository"))
  end

  defp mask_token(token) when is_binary(token) do
    if String.length(token) > 8 do
      String.slice(token, 0, 8) <> "..."
    else
      "***"
    end
  end

  defp mask_token(_), do: "***"

  defp atomize_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
