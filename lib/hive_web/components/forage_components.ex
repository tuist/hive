defmodule HiveWeb.ForageComponents do
  @moduledoc """
  Presentational components for the forage LiveViews: the feature-request
  list, the new-request form, and the placeholder sources. They render
  the `#forage` body only; the surrounding chrome comes from
  `HiveWeb.Layouts.dashboard` and the document from the root layout.
  """

  use HiveWeb, :html

  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GrafanaAlert
  alias Hive.Meadows.GitHubRepository
  alias HiveWeb.Markdown

  attr :source, :map, required: true
  attr :feature_requests, :list, required: true
  attr :signed_in?, :boolean, required: true
  attr :can_create_spec?, :boolean, default: false

  def feature_requests(assigns) do
    assigns = assign(assigns, :stats, stats(assigns.feature_requests))

    ~H"""
    <section id="forage">
      <.forage_header source={@source} signed_in?={@signed_in?} />

      <div data-part="widgets">
        <.forage_widget title="Total requests" value={@stats.total} legend="primary" />
        <.forage_widget title="Open" value={@stats.open} legend="secondary" />
        <.forage_widget title="Contributors" value={@stats.contributors} legend="tertiary" />
      </div>

      <.card icon={@source.icon} title={@source.label}>
        <.card_section>
          <div :if={@feature_requests == []} data-part="empty-state">
            <div data-part="empty-icon"><.bulb /></div>
            <h2>No feature requests yet</h2>
            <p>Public ideas submitted here will appear as forage for the hive.</p>
            <.button
              label={if @signed_in?, do: "Create the first request", else: "Log in to request"}
              href={if @signed_in?, do: ~p"/forage/feature-requests/new", else: ~p"/login"}
              size="medium"
              variant="secondary"
            />
          </div>

          <div :if={@feature_requests != []} data-part="request-list">
            <article :for={feature_request <- @feature_requests} data-part="request-row">
              <div data-part="request-copy">
                <h2>{feature_request.title}</h2>
                <p>{feature_request.description}</p>
                <span data-part="requester">{requester_label(feature_request)}</span>
              </div>
              <div data-part="request-meta">
                <.badge
                  label={status_label(feature_request.status)}
                  color={status_color(feature_request.status)}
                  style="light-fill"
                  size="large"
                  dot={true}
                />
                <.badge label="Public" color="success" style="light-fill" size="large" />
                <.button
                  :if={@can_create_spec?}
                  label="Create spec"
                  href={~p"/specs/new?source_feature_request_id=#{feature_request.id}"}
                  size="small"
                  variant="secondary"
                />
              </div>
            </article>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :form, :any, required: true
  attr :user_name, :string, required: true

  def new_feature_request(assigns) do
    ~H"""
    <section id="forage">
      <div data-part="header">
        <div data-part="title-group">
          <.badge label="Forage" color="information" style="light-fill" />
          <h1>New feature request</h1>
          <p>Capture a public idea that can become workable meadow direction.</p>
          <span data-part="requester">
            Requesting as {@user_name}
          </span>
        </div>
        <.button label="Back" href={~p"/forage/feature-requests"} size="medium" variant="secondary">
          <:icon_left><.arrow_left /></:icon_left>
        </.button>
      </div>

      <.card icon="bulb" title="Request details" data-part="form-card">
        <.card_section>
          <.form for={@form} phx-change="validate" phx-submit="save" data-part="form">
            <.text_input
              field={@form[:title]}
              label="Title"
              placeholder="Describe the capability in one sentence"
              required={true}
              show_required={true}
            />
            <.text_area
              field={@form[:description]}
              label="Description"
              placeholder="Explain the problem, who needs it, and why it matters."
              max_length={2_000}
              rows={8}
              required={true}
              show_required={true}
            />
            <div data-part="form-actions">
              <.button label="Submit request" size="medium" variant="primary" />
            </div>
          </.form>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :source, :map, required: true
  attr :alerts, :list, required: true

  def grafana_alerts(assigns) do
    assigns = assign(assigns, :stats, grafana_stats(assigns.alerts))

    ~H"""
    <section id="forage">
      <.forage_header source={@source} signed_in?={true} />

      <div data-part="widgets">
        <.forage_widget title="Active" value={@stats.firing} legend="primary" />
        <.forage_widget title="Resolved" value={@stats.resolved} legend="secondary" />
        <.forage_widget title="Meadows" value={@stats.meadows} legend="tertiary" />
      </div>

      <.card icon={@source.icon} title={@source.label}>
        <.card_section>
          <div :if={@alerts == []} data-part="empty-state">
            <div data-part="empty-icon"><.bell /></div>
            <h2>No Grafana alerts yet</h2>
            <p>
              Generate a webhook on a meadow in settings and point a Grafana
              contact point at it. Firing and resolved deliveries will thread
              into one item per alert.
            </p>
          </div>

          <div :if={@alerts != []} data-part="request-list">
            <article :for={alert <- @alerts} data-part="request-row">
              <div data-part="request-copy">
                <h2>{alert.title}</h2>
                <p :if={alert.summary}>{alert.summary}</p>
                <span data-part="requester">{grafana_meta(alert)}</span>
              </div>
              <div data-part="request-meta">
                <.badge
                  label={GrafanaAlert.status_label(alert.status)}
                  color={GrafanaAlert.status_color(alert.status)}
                  style="light-fill"
                  size="large"
                  dot={true}
                />
                <.badge
                  :if={alert.meadow}
                  label={alert.meadow.name}
                  color="neutral"
                  style="light-fill"
                  size="large"
                />
                <.button
                  :if={alert.generator_url}
                  label="Open in Grafana"
                  href={alert.generator_url}
                  size="small"
                  variant="secondary"
                />
              </div>
            </article>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  defp grafana_stats(alerts) do
    %{
      firing: Enum.count(alerts, &(&1.status == :firing)),
      resolved: Enum.count(alerts, &(&1.status == :resolved)),
      meadows: alerts |> Enum.map(& &1.meadow_id) |> Enum.uniq() |> length()
    }
  end

  defp grafana_meta(alert) do
    "Last received #{Calendar.strftime(alert.last_received_at, "%Y-%m-%d %H:%M UTC")}"
  end

  attr :source, :map, required: true
  attr :signed_in?, :boolean, required: true
  attr :entries, :list, required: true
  attr :stats, :map, required: true
  attr :available_filters, :list, required: true
  attr :active_filters, :list, required: true

  def github_issues(assigns) do
    ~H"""
    <section id="forage">
      <.forage_header source={@source} signed_in?={@signed_in?} />

      <div data-part="widgets">
        <.forage_widget title={String.capitalize(@stats.state_label)} value={@stats.total} legend="primary" />
        <.forage_widget title="Repositories" value={@stats.repositories} legend="secondary" />
        <.forage_widget title="Meadows" value={@stats.meadows} legend="tertiary" />
      </div>

      <.card icon={@source.icon} title={@source.label}>
        <.card_section>
          <div data-part="filters">
            <.filter_dropdown
              id="github-issues-filter"
              label="Filter"
              available_filters={@available_filters}
              active_filters={@active_filters}
              on_select="add_filter"
            />
          </div>
          <div :if={@active_filters != []} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>

          <div :if={@entries == []} data-part="empty-state">
            <div data-part="empty-icon"><.icon name={@source.icon} /></div>
            <h2>No {@stats.state_label} to show</h2>
            <p>
              Connect a GitHub repository to a meadow in
              <a href={~p"/meadows"}>Meadows</a>
              and matching issues will appear here once they have been synced.
            </p>
          </div>

          <div :if={@entries != []} data-part="issue-list">
            <article :for={{meadow, repository, issue} <- @entries} data-part="issue-row">
              <div data-part="issue-copy">
                <h2>
                  <a
                    href={GitHubIssue.html_url(%{issue | github_repository: repository})}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {Markdown.inline(issue.title)}
                  </a>
                </h2>
                <p :if={issue_excerpt(issue.body)}>{Markdown.inline(issue_excerpt(issue.body))}</p>
                <div data-part="issue-meta-row">
                  <.badge
                    label={GitHubRepository.full_name(repository)}
                    color="neutral"
                    style="light-fill"
                    size="large"
                  >
                    <:icon><.brand_github /></:icon>
                  </.badge>
                  <.badge
                    label={meadow.name}
                    color="information"
                    style="light-fill"
                    size="large"
                  />
                </div>
              </div>
              <div data-part="issue-actions">
                <.badge
                  label={"##{issue.number}"}
                  color="neutral"
                  style="light-fill"
                  size="large"
                />
                <.button
                  label="View on GitHub"
                  href={GitHubIssue.html_url(%{issue | github_repository: repository})}
                  size="small"
                  variant="secondary"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <:icon_left><.brand_github /></:icon_left>
                </.button>
              </div>
            </article>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :source, :map, required: true
  attr :signed_in?, :boolean, required: true

  def placeholder(assigns) do
    ~H"""
    <section id="forage">
      <.forage_header source={@source} signed_in?={@signed_in?} />
      <.card icon={@source.icon} title={@source.label}>
        <.card_section>
          <div data-part="empty-state">
            <div data-part="empty-icon"><.icon name={@source.icon} /></div>
            <h2>This forage source is not connected yet</h2>
            <p>The source is modeled so access can be gated before ingestion is implemented.</p>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :source, :map, required: true
  attr :signed_in?, :boolean, required: true

  defp forage_header(assigns) do
    ~H"""
    <div data-part="header">
      <div data-part="title-group">
        <.badge label="Forage" color="information" style="light-fill" />
        <h1>{@source.label}</h1>
        <p>{@source.description}</p>
      </div>
      <.button
        :if={@source.id == :feature_requests}
        label={if @signed_in?, do: "New request", else: "Log in to request"}
        href={if @signed_in?, do: ~p"/forage/feature-requests/new", else: ~p"/login"}
        size="medium"
        variant="primary"
      >
        <:icon_left>
          <.circle_plus :if={@signed_in?} />
          <.lock :if={!@signed_in?} />
        </:icon_left>
      </.button>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :legend, :string, default: "primary"

  defp forage_widget(assigns) do
    ~H"""
    <div data-part="widget">
      <div data-part="widget-header">
        <span data-part="legend" data-color={@legend}></span>
        <span data-part="widget-title">{@title}</span>
      </div>
      <span data-part="widget-value">{@value}</span>
    </div>
    """
  end

  defp stats(feature_requests) do
    %{
      total: length(feature_requests),
      open: Enum.count(feature_requests, &(&1.status == :open)),
      contributors:
        feature_requests
        |> Enum.map(& &1.user_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> length()
    }
  end

  defp status_label(status), do: status |> Atom.to_string() |> String.capitalize()

  defp status_color(:open), do: "information"
  defp status_color(:planned), do: "attention"
  defp status_color(:closed), do: "neutral"

  defp requester_label(%{user: %{email: email}}) when is_binary(email),
    do: "Submitted by #{email}"

  defp requester_label(_feature_request), do: "Submitted anonymously"

  defp issue_excerpt(nil), do: nil
  defp issue_excerpt(""), do: nil

  defp issue_excerpt(body) when is_binary(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.find(&excerpt_candidate?/1)
    |> case do
      nil -> nil
      line -> truncate(line, 240)
    end
  end

  defp excerpt_candidate?(""), do: false
  defp excerpt_candidate?(line), do: not Regex.match?(~r/^#+\s+/, line)

  defp truncate(string, limit) when byte_size(string) <= limit, do: string
  defp truncate(string, limit), do: String.slice(string, 0, limit) <> "…"
end
