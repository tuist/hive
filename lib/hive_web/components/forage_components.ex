defmodule HiveWeb.ForageComponents do
  @moduledoc """
  Presentational components for the forage LiveViews: the feature-request
  list, the new-request form, and the placeholder sources. They render
  the `#forage` body only; the surrounding chrome comes from
  `HiveWeb.Layouts.dashboard` and the document from the root layout.
  """

  use HiveWeb, :html

  alias Hive.Forage
  alias Hive.Forage.Comment
  alias Hive.Forage.FeatureRequest
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GrafanaAlert
  alias Hive.Domains.GitHubRepository
  alias HiveWeb.Layouts
  alias HiveWeb.Markdown

  @heading_line ~r/^#+\s+/

  attr :items, :list, required: true
  attr :stats, :map, required: true
  attr :meta, :map, required: true
  attr :search_form, :any, required: true
  attr :available_filters, :list, required: true
  attr :active_filters, :list, required: true
  attr :signed_in?, :boolean, required: true
  attr :can_create_spec?, :boolean, default: false
  attr :current_path, :string, required: true
  attr :page_link, :any, required: true
  attr :item_link, :any, required: true

  def items(assigns) do
    ~H"""
    <section id="forage">
      <div data-part="header">
        <div data-part="title-group">
          <h1>Forage</h1>
          <p>Feature requests, bug reports, feedback, GitHub issues, and Grafana alerts in one queue.</p>
        </div>
        <div data-part="header-actions">
          <Layouts.feeds_dropdown
            id="forage-feeds-dropdown"
            atom_href="/forage/atom.xml"
            rss_href="/forage/rss.xml"
          />
          <.button
            label={if @signed_in?, do: "New item", else: "Log in to submit"}
            href={
              if @signed_in?,
                do: ~p"/forage/new",
                else: ~p"/login?#{[return_to: @current_path]}"
            }
            size="medium"
            variant="primary"
          >
            <:icon_left>
              <.circle_plus :if={@signed_in?} />
              <.lock :if={!@signed_in?} />
            </:icon_left>
          </.button>
        </div>
      </div>

      <div data-part="widgets">
        <.forage_widget title="Items" value={@stats.total} legend="primary" />
        <.forage_widget title="Open signals" value={@stats.open} legend="secondary" />
        <.forage_widget title="Domains" value={@stats.domains} legend="tertiary" />
      </div>

      <.card icon="rss" title="Forage items">
        <.card_section>
          <div data-part="table-toolbar">
            <.filter_dropdown
              id="forage-filter"
              label="Filter"
              available_filters={@available_filters}
              active_filters={@active_filters}
              on_select="add_filter"
            />

            <div data-part="search">
              <.form
                id="forage-search-form"
                for={@search_form}
                phx-change="search"
                phx-submit="search"
              >
                <.text_input
                  id="forage-search"
                  field={@search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder="Search forage..."
                />
              </.form>
            </div>
          </div>

          <div :if={@active_filters != []} data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>

          <div :if={@items == []} data-part="empty-state">
            <div data-part="empty-icon"><.icon name="rss" /></div>
            <h2>No forage items found</h2>
            <p>Items that match the active filters will appear here.</p>
          </div>

          <.table :if={@items != []} id="forage-items-table" rows={@items}>
            <:col :let={item} label="Item">
              <div data-part="item-table-cell">
                <.icon name={item_icon(item.type)} />
                <div data-part="item-table-copy">
                  <strong>
                    <.link navigate={@item_link.(item)} data-part="item-title-link">
                      {Markdown.inline(item.title)}
                    </.link>
                  </strong>
                  <p :if={item_excerpt(item.body)}>{Markdown.inline(item_excerpt(item.body))}</p>
                </div>
              </div>
            </:col>
            <:col :let={item} label="Type">
              <.badge_cell
                label={Forage.item_type_label(item.type)}
                color={type_color(item.type)}
                style="light-fill"
              />
            </:col>
            <:col :let={item} label="Status">
              <.badge_cell
                label={Forage.item_status_label(item.status)}
                color={Forage.item_status_color(item.status)}
                style="light-fill"
              />
            </:col>
            <:col :let={item} label="Domains">
              <div data-part="item-table-domains">
                <.badge
                  :for={domain <- item.domains}
                  label={domain.name}
                  color="neutral"
                  style="light-fill"
                  size="large"
                />
                <span :if={item.domains == []} data-part="empty-domains">
                  No domains
                </span>
              </div>
            </:col>
            <:col :let={item} label="Source">
              <div data-part="item-table-source">
                <span>{item.source_label || "-"}</span>
                <span :if={item.external_label}>{item.external_label}</span>
              </div>
            </:col>
            <:col :let={item} label="Updated">
              <.time_cell time={item.updated_at} />
            </:col>
            <:col :let={item} label="Actions">
              <div data-part="item-actions">
                <.button
                  :if={@can_create_spec? and item.origin == :manual}
                  label="Create spec"
                  href={~p"/specs/new?source_feature_request_id=#{item.source_record_id}"}
                  size="small"
                  variant="secondary"
                />
                <.button
                  :if={item.external_url}
                  label={external_action_label(item)}
                  href={item.external_url}
                  size="small"
                  variant="secondary"
                  icon_only={true}
                  aria-label={external_action_label(item)}
                  title={external_action_label(item)}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <.icon name={external_action_icon(item)} />
                </.button>
              </div>
            </:col>
          </.table>

          <div :if={@meta.total_pages > 1} data-part="pagination">
            <.button
              variant="secondary"
              label="Prev"
              disabled={@meta.current_page <= 1}
              patch={@page_link.(max(1, @meta.current_page - 1))}
            >
              <:icon_left><.chevron_left /></:icon_left>
            </.button>
            <.button
              variant="secondary"
              label="Next"
              disabled={@meta.current_page >= @meta.total_pages}
              patch={@page_link.(min(@meta.total_pages, @meta.current_page + 1))}
            >
              <:icon_right><.chevron_right /></:icon_right>
            </.button>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :item, :map, required: true
  attr :can_create_spec?, :boolean, required: true
  attr :can_edit_item?, :boolean, required: true
  attr :can_comment_item?, :boolean, required: true
  attr :editing_item?, :boolean, required: true
  attr :item_edit_form, :any, required: true
  attr :comment_form, :any, required: true
  attr :edit_comment_form, :any, required: true
  attr :editing_comment_id, :string, default: nil
  attr :signed_in?, :boolean, required: true
  attr :current_path, :string, required: true
  attr :current_user, :map, default: nil

  def item_detail(assigns) do
    ~H"""
    <section id="forage">
      <div data-part="header">
        <div data-part="title-group">
          <h1>{Markdown.inline(@item.title)}</h1>
          <div data-part="detail-kicker">
            <.badge
              label={Forage.item_type_label(@item.type)}
              color={type_color(@item.type)}
              style="light-fill"
            />
            <.badge
              label={Forage.item_status_label(@item.status)}
              color={Forage.item_status_color(@item.status)}
              style="light-fill"
            />
          </div>
        </div>

        <div data-part="header-actions">
          <.button
            :if={@can_edit_item? and !@editing_item?}
            label="Edit"
            size="medium"
            variant="secondary"
            phx-click="edit_item"
          >
            <:icon_left><.pencil /></:icon_left>
          </.button>
          <.button
            :if={@can_create_spec? and @item.origin == :manual}
            label="Create spec"
            href={~p"/specs/new?source_feature_request_id=#{@item.source_record_id}"}
            size="medium"
            variant="secondary"
          />
          <.button
            :if={@item.external_url}
            label={external_action_label(@item)}
            href={@item.external_url}
            size="medium"
            variant="secondary"
            target="_blank"
            rel="noopener noreferrer"
          />
        </div>
      </div>

      <.card title="Details" icon={item_icon(@item.type)} data-part="details-card">
        <.card_section data-part="details-card-section">
          <.form
            :if={@editing_item?}
            for={@item_edit_form}
            phx-change="validate_item_edit"
            phx-submit="update_item"
            data-part="item-edit-form"
          >
            <.item_type_select form={@item_edit_form} id="forage-item-edit-type" />
            <.text_input
              field={@item_edit_form[:title]}
              label="Title"
              required={true}
              show_required={true}
            />
            <.text_area
              field={@item_edit_form[:description]}
              label="Description"
              max_length={2_000}
              rows={8}
              required={true}
              show_required={true}
            />
            <div data-part="form-actions">
              <.button
                label="Cancel"
                size="medium"
                variant="secondary"
                type="button"
                phx-click="cancel_item_edit"
              />
              <.button label="Save item" size="medium" variant="primary" />
            </div>
          </.form>

          <div :if={!@editing_item?} data-part="detail-body">
            {Markdown.render(@item.body)}
          </div>

          <div data-part="metadata-grid">
            <div data-part="metadata-row">
              <div data-part="metadata">
                <div data-part="title">Source</div>
                <span data-part="label">
                  {@item.source_label}{if @item.external_label, do: " #{@item.external_label}"}
                </span>
              </div>
              <div :if={@item.requester_label} data-part="metadata">
                <div data-part="title">Requester</div>
                <span data-part="label">{@item.requester_label}</span>
              </div>
              <div data-part="metadata">
                <div data-part="title">Updated</div>
                <span data-part="label">{Calendar.strftime(@item.updated_at, "%b %-d, %Y")}</span>
              </div>
            </div>

            <div :if={@item.domains != []} data-part="metadata-row">
              <div data-part="metadata">
                <div data-part="title">Domains</div>
                <div data-part="metadata-badges">
                  <.badge
                    :for={domain <- @item.domains}
                    label={domain.name}
                    color="neutral"
                    style="light-fill"
                    size="large"
                  />
                </div>
              </div>
            </div>
          </div>
        </.card_section>
      </.card>

      <.card title="Comments" icon="message_circle" data-part="comments-card">
        <.card_section data-part="comments-card-section">
          <.comments_list
            item={@item}
            edit_comment_form={@edit_comment_form}
            editing_comment_id={@editing_comment_id}
            current_user={@current_user}
          />

          <.form
            :if={@can_comment_item?}
            for={@comment_form}
            phx-submit="comment"
            data-part="comment-form"
          >
            <.text_area
              field={@comment_form[:body]}
              label="Comment"
              placeholder="Add context or feedback with Markdown"
              max_length={20_000}
              rows={5}
              required={true}
              show_required={true}
            />
            <div data-part="form-actions">
              <.button label="Comment" size="medium" variant="primary" />
            </div>
          </.form>

          <.alert
            :if={!@signed_in? and @item.origin == :manual}
            status="information"
            type="secondary"
            size="large"
            title="Sign in to comment"
            data-part="comment-auth-required"
          >
            <p>Comments are available to authenticated users.</p>
            <:action>
              <.button
                label="Sign in"
                href={~p"/login?#{[return_to: @current_path]}"}
                size="medium"
                variant="secondary"
              />
            </:action>
          </.alert>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :item, :map, required: true
  attr :edit_comment_form, :any, required: true
  attr :editing_comment_id, :string, default: nil
  attr :current_user, :map, default: nil

  defp comments_list(assigns) do
    ~H"""
    <div :if={@item.comments_status == :error} data-part="comments-unavailable">
      <.alert status="information" type="secondary" size="large" title="GitHub comments unavailable">
        <p>Open the issue on GitHub to read or add comments.</p>
      </.alert>
    </div>

    <div :if={@item.comments_status != :error and @item.comments == []} data-part="empty-comments">
      <p>{empty_comments_text(@item)}</p>
    </div>

    <div :if={@item.comments_status != :error and @item.comments != []} data-part="comment-list">
      <article :for={comment <- @item.comments} id={"forage-comment-#{comment_id(comment)}"} data-part="comment">
        <.avatar
          id={"forage-comment-avatar-#{comment_id(comment)}"}
          name={comment_author(comment)}
          image_href={comment_avatar_url(comment)}
          color={avatar_color(comment_author(comment))}
          size="small"
        />
        <div data-part="comment-card">
          <header data-part="comment-header">
            <div data-part="comment-author">
              <strong>{comment_author(comment)}</strong>
              <span>{comment_timestamp(comment)}</span>
            </div>
            <div data-part="comment-actions">
              <button
                :if={comment_editable?(comment, @current_user)}
                type="button"
                data-part="comment-action-button"
                phx-click="edit_comment"
                phx-value-id={comment.id}
                aria-label="Edit comment"
                title="Edit comment"
              >
                <.pencil />
              </button>
              <a
                :if={comment_permalink(comment)}
                href={comment_permalink(comment)}
                target="_blank"
                rel="noopener noreferrer"
                data-part="comment-permalink"
                aria-label="Open comment"
                title="Open comment"
              >
                <.icon name="external_link" />
              </a>
            </div>
          </header>

          <.form
            :if={@editing_comment_id == comment_id(comment)}
            for={@edit_comment_form}
            phx-change="validate_comment_edit"
            phx-submit="update_comment"
            data-part="comment-edit-form"
          >
            <input type="hidden" name="comment_id" value={comment_id(comment)} />
            <.text_area
              field={@edit_comment_form[:body]}
              label="Edit comment"
              max_length={20_000}
              rows={5}
              required={true}
              show_required={true}
            />
            <div data-part="form-actions">
              <.button
                label="Cancel"
                size="medium"
                variant="secondary"
                type="button"
                phx-click="cancel_comment_edit"
              />
              <.button label="Save comment" size="medium" variant="primary" />
            </div>
          </.form>

          <div :if={@editing_comment_id != comment_id(comment)} data-part="comment-body">
            {Markdown.render(comment_body(comment))}
          </div>
        </div>
      </article>
    </div>
    """
  end

  defp comment_id(%{id: id}) when is_integer(id), do: Integer.to_string(id)
  defp comment_id(%{id: id}) when is_binary(id), do: id
  defp comment_id(_comment), do: "unknown"

  defp comment_author(%{user: %{email: email}}) when is_binary(email), do: email
  defp comment_author(%{user_login: login}) when is_binary(login), do: login
  defp comment_author(_comment), do: "Unknown"

  defp comment_body(%{body: body}) when is_binary(body), do: body
  defp comment_body(_comment), do: ""

  defp comment_timestamp(%{inserted_at: %DateTime{} = inserted_at}) do
    Calendar.strftime(inserted_at, "%b %-d, %Y")
  end

  defp comment_timestamp(%{created_at: created_at}) when is_binary(created_at) do
    case DateTime.from_iso8601(created_at) do
      {:ok, created_at, _offset} -> Calendar.strftime(created_at, "%b %-d, %Y")
      _error -> "GitHub"
    end
  end

  defp comment_timestamp(_comment), do: ""

  defp comment_avatar_url(%{user_avatar_url: url}) when is_binary(url), do: url
  defp comment_avatar_url(%{user: user}), do: avatar_url(user)
  defp comment_avatar_url(_comment), do: nil

  defp comment_permalink(%{html_url: url}) when is_binary(url), do: url
  defp comment_permalink(_comment), do: nil

  defp comment_editable?(%Comment{} = comment, current_user) do
    Forage.can_edit_comment?(comment, current_user)
  end

  defp comment_editable?(_comment, _current_user), do: false

  defp empty_comments_text(%{origin: :github, comments_status: :loaded}),
    do: "No GitHub comments yet."

  defp empty_comments_text(%{origin: :manual}), do: "No comments yet."
  defp empty_comments_text(_item), do: "No comments available."

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
              href={if @signed_in?, do: ~p"/forage/new", else: ~p"/login"}
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

  def new_item(assigns) do
    ~H"""
    <section id="forage">
      <div data-part="header">
        <div data-part="title-group">
          <h1>New forage item</h1>
          <p>Capture a public feature request, bug report, or feedback item.</p>
          <span data-part="requester">
            Requesting as {@user_name}
          </span>
        </div>
      </div>

      <.card icon="rss" title="Item details" data-part="form-card">
        <.card_section>
          <.form for={@form} phx-change="validate" phx-submit="save" data-part="form">
            <.item_type_select form={@form} id="forage-item-type" />
            <.text_input
              field={@form[:title]}
              label="Title"
              placeholder="Describe the item in one sentence"
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
              <.button label="Submit item" size="medium" variant="primary" />
            </div>
          </.form>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :form, :any, required: true
  attr :user_name, :string, required: true

  def new_feature_request(assigns), do: new_item(assigns)

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
        <.forage_widget title="Projects" value={@stats.projects} legend="tertiary" />
      </div>

      <.card icon={@source.icon} title={@source.label}>
        <.card_section>
          <div :if={@alerts == []} data-part="empty-state">
            <div data-part="empty-icon"><.bell /></div>
            <h2>No Grafana alerts yet</h2>
            <p>
              Generate a webhook on a project and point a Grafana
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
                  :if={alert.project}
                  label={alert.project.name}
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
      projects: alerts |> Enum.map(& &1.project_id) |> Enum.uniq() |> length()
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
        <.forage_widget title="Domains" value={@stats.domains} legend="tertiary" />
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
              Connect a GitHub repository to a domain in
              <a href={~p"/domains"}>Domains</a>
              and matching issues will appear here once they have been synced.
            </p>
          </div>

          <div :if={@entries != []} data-part="issue-list">
            <article :for={{repository, issue, domains} <- @entries} data-part="issue-row">
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
                    :for={domain <- domains}
                    label={domain.name}
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
        <h1>{@source.label}</h1>
        <p>{@source.description}</p>
      </div>
      <div data-part="header-actions">
        <Layouts.feeds_dropdown
          id={"forage-#{@source.id}-feeds-dropdown"}
          atom_href={"#{@source.path}/atom.xml"}
          rss_href={"#{@source.path}/rss.xml"}
        />
        <.button
          :if={@source.id == :feature_requests}
          label={if @signed_in?, do: "New request", else: "Log in to request"}
          href={if @signed_in?, do: ~p"/forage/new", else: ~p"/login"}
          size="medium"
          variant="primary"
        >
          <:icon_left>
            <.circle_plus :if={@signed_in?} />
            <.lock :if={!@signed_in?} />
          </:icon_left>
        </.button>
      </div>
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

  attr :form, :any, required: true
  attr :id, :string, required: true

  defp item_type_select(assigns) do
    assigns =
      assign(
        assigns,
        :value,
        Phoenix.HTML.Form.normalize_value("select", assigns.form[:type].value)
      )

    ~H"""
    <div data-part="select-field">
      <span>Type</span>
      <.select id={@id} name={@form[:type].name} value={@value} label="Choose type">
        <:item
          :for={type <- FeatureRequest.types()}
          value={Atom.to_string(type)}
          label={Forage.item_type_label(type)}
          icon={item_icon(type)}
        />
      </.select>
    </div>
    """
  end

  defp item_icon(:feature_request), do: "bulb"
  defp item_icon(:bug_report), do: "file_alert"
  defp item_icon(:feedback), do: "message_circle"
  defp item_icon(:github_issue), do: "brand_github"
  defp item_icon(:grafana_alert), do: "bell"
  defp item_icon(_type), do: "rss"

  defp type_color(:feature_request), do: "information"
  defp type_color(:bug_report), do: "attention"
  defp type_color(:feedback), do: "success"
  defp type_color(:github_issue), do: "neutral"
  defp type_color(:grafana_alert), do: "attention"
  defp type_color(_type), do: "neutral"

  defp external_action_label(%{type: :github_issue}), do: "Open on GitHub"
  defp external_action_label(%{type: :grafana_alert}), do: "Open in Grafana"
  defp external_action_label(_item), do: "Open"

  defp external_action_icon(%{type: :github_issue}), do: "brand_github"
  defp external_action_icon(_item), do: "external_link"

  defp item_excerpt(nil), do: nil
  defp item_excerpt(""), do: nil

  defp item_excerpt(body) when is_binary(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.find(&excerpt_candidate?/1)
    |> case do
      nil -> nil
      line -> truncate(line, 180)
    end
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
  defp excerpt_candidate?(line), do: not Regex.match?(@heading_line, line)

  defp avatar_url(%{email: email, identities: identities}) when is_list(identities) do
    github_avatar_url(identities) || gravatar_url(email)
  end

  defp avatar_url(%{email: email}) when is_binary(email), do: gravatar_url(email)
  defp avatar_url(_user), do: nil

  defp github_avatar_url(identities) do
    identities
    |> Enum.find(&(&1.provider == "github" and String.match?(&1.provider_uid, ~r/^\d+$/)))
    |> case do
      nil -> nil
      identity -> "https://avatars.githubusercontent.com/u/#{identity.provider_uid}?v=4"
    end
  end

  defp gravatar_url(email) when is_binary(email) do
    hash =
      email
      |> String.trim()
      |> String.downcase()
      |> then(&:crypto.hash(:md5, &1))
      |> Base.encode16(case: :lower)

    "https://www.gravatar.com/avatar/#{hash}?d=identicon"
  end

  defp avatar_color(author) do
    colors = ~w(gray red orange yellow azure blue purple pink)
    Enum.at(colors, :erlang.phash2(author, length(colors)))
  end

  defp truncate(string, limit) when byte_size(string) <= limit, do: string
  defp truncate(string, limit), do: String.slice(string, 0, limit) <> "…"
end
