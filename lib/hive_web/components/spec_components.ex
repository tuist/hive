defmodule HiveWeb.SpecComponents do
  @moduledoc false

  use HiveWeb, :html

  alias Hive.Specs
  alias Hive.Specs.Spec
  alias HiveWeb.Layouts
  alias HiveWeb.Markdown
  alias HiveWeb.MentionComponents

  attr :specs, :list, required: true
  attr :can_create?, :boolean, required: true
  attr :available_filters, :list, required: true
  attr :active_filters, :list, required: true

  def index(assigns) do
    ~H"""
    <section id="specs">
      <div data-part="header">
        <div data-part="title-group">
          <h1>{dgettext("dashboard_specs", "Specs")}</h1>
          <p>{dgettext("dashboard_specs", "Editable proposals that shape forage into buildable work.")}</p>
        </div>
        <div data-part="header-actions">
          <Layouts.feeds_dropdown
            id="specs-index-feeds-dropdown"
            atom_href="/specs/atom.xml"
            rss_href="/specs/rss.xml"
          />
          <.button
            :if={@can_create?}
            label={dgettext("dashboard_specs", "New spec")}
            href={~p"/specs/new"}
            size="medium"
            variant="primary"
          >
            <:icon_left><.circle_plus /></:icon_left>
          </.button>
        </div>
      </div>

      <.card icon="file_text" title={dgettext("dashboard_specs", "Specs")}>
        <.card_section>
          <div data-part="table-toolbar">
            <.filter_dropdown
              id="specs-filter"
              label={dgettext("dashboard_specs", "Filter")}
              available_filters={@available_filters}
              active_filters={@active_filters}
              on_select="add_filter"
            />
            <div data-part="active-filters">
              <.active_filter :for={filter <- @active_filters} filter={filter} />
            </div>
          </div>

          <div :if={@specs == []} data-part="empty-state">
            <div data-part="empty-icon"><.icon name="file_text" /></div>
            <h2>{dgettext("dashboard_specs", "No specs yet")}</h2>
            <p>{dgettext("dashboard_specs", "Specs that match the active filters will appear here.")}</p>
          </div>

          <.table
            :if={@specs != []}
            id="specs-table"
            rows={@specs}
            row_navigate={fn spec -> ~p"/specs/#{spec.number}" end}
          >
            <:col :let={spec} label={dgettext("dashboard_specs", "Spec")}>
              <div data-part="spec-table-cell">
                <.icon name="file_text" />
                <div data-part="spec-table-copy">
                  <div data-part="spec-title-row">
                    <strong>{spec_number(spec)} {spec.title}</strong>
                    <.badge
                      :if={spec.has_new_activity}
                      label={dgettext("dashboard_specs", "New activity")}
                      color="information"
                      style="light-fill"
                    />
                  </div>
                  <p>
                    {project_label(spec)} · {visibility_label(Specs.effective_visibility(spec))} · {Markdown.preview(spec.body)}
                  </p>
                </div>
              </div>
            </:col>
            <:col :let={spec} label={dgettext("dashboard_specs", "Source")}>
              <span data-part="spec-table-source">{source_label(spec)}</span>
            </:col>
            <:col :let={spec} label={dgettext("dashboard_specs", "Domains")}>
              <div data-part="spec-table-domains">
                <.badge
                  :for={domain <- spec_domains(spec)}
                  label={domain.name}
                  color="neutral"
                  style="light-fill"
                  size="large"
                />
                <span :if={spec_domains(spec) == []} data-part="empty-domains">
                  {dgettext("dashboard_specs", "No domains")}
                </span>
              </div>
            </:col>
            <:col :let={spec} label={dgettext("dashboard_specs", "Status")}>
              <.badge_cell
                label={status_label(spec.status)}
                color={status_color(spec.status)}
                style="light-fill"
              />
            </:col>
            <:col :let={spec} label={dgettext("dashboard_specs", "Updated")}>
              <.time_cell time={spec.updated_at} />
            </:col>
          </.table>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :spec, :map, required: true
  attr :comment_form, :any, required: true
  attr :edit_comment_form, :any, required: true
  attr :mention_suggestions, :list, default: []
  attr :can_edit?, :boolean, required: true
  attr :can_request_review?, :boolean, required: true
  attr :current_user, :map, default: nil
  attr :editing_comment_id, :string, default: nil
  attr :signed_in?, :boolean, required: true
  attr :current_path, :string, required: true
  attr :expanded_revision_rows, :list, required: true
  attr :viewer_last_viewed_at, :any, default: nil
  attr :revision_summaries_enabled?, :boolean, default: false

  def show(assigns) do
    assigns = assign(assigns, :new_activity_since_visit?, new_activity_since_visit?(assigns))

    ~H"""
    <section id="specs">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{@spec.title}</h1>
            <p>
              {spec_number(@spec)} · {project_label(@spec)} · {visibility_label(Specs.effective_visibility(@spec))} · {source_label(@spec)}
              <span :if={@new_activity_since_visit?}>
                · {dgettext("dashboard_specs", "New activity")}
              </span>
            </p>
            <div :if={spec_domains(@spec) != []} data-part="domain-list">
              <.badge
                :for={domain <- spec_domains(@spec)}
              label={domain.name}
              color="neutral"
              style="light-fill"
            />
          </div>
        </div>
        <div data-part="header-actions">
          <Layouts.feeds_dropdown
            id="spec-show-feeds-dropdown"
            atom_href="/specs/atom.xml"
            rss_href="/specs/rss.xml"
          />
          <.button
            :if={@can_request_review?}
            label={dgettext("dashboard_specs", "Ask for review")}
            size="medium"
            variant="secondary"
            phx-click="request_review"
          >
            <:icon_left><.bell /></:icon_left>
          </.button>
          <.status_menu :if={@can_edit?} spec={@spec} />
          <.badge
            :if={!@can_edit?}
            label={status_label(@spec.status)}
            color={status_color(@spec.status)}
            style="light-fill"
            size="large"
          />
          <.button
            :if={@can_edit?}
            label={dgettext("dashboard_specs", "Edit")}
            href={~p"/specs/#{@spec.number}/edit"}
            size="medium"
            variant="primary"
          >
            <:icon_left><.pencil /></:icon_left>
          </.button>
        </div>
      </div>

      <div data-part="detail-stack">
        <.card icon="file_text" title={dgettext("dashboard_specs", "Proposal")}>
          <.card_section>
            <div data-part="spec-body">
              {Markdown.render(@spec.body)}
            </div>
          </.card_section>
        </.card>

        <.card icon="git_branch" title={dgettext("dashboard_specs", "Draft history")}>
          <.card_section>
            <.table
              id="spec-revisions-table"
              rows={@spec.revisions}
              row_key={&revision_row_key/1}
              row_expandable={fn _revision -> true end}
              expanded_rows={@expanded_revision_rows}
            >
              <:col :let={revision} label={dgettext("dashboard_specs", "Revision")}>
                <.text_cell
                  label={
                    dgettext("dashboard_specs", "Revision %{revision}",
                      revision: revision.revision
                    )
                  }
                  sublabel={revision_author(revision)}
                  icon="git_commit"
                />
              </:col>
              <:col :let={revision} label={dgettext("dashboard_specs", "Status")}>
                <.badge_cell
                  label={status_label(revision.status)}
                  color={status_color(revision.status)}
                  style="light-fill"
                />
              </:col>
              <:col :let={revision} label={dgettext("dashboard_specs", "Edited")}>
                <.time_cell time={revision.inserted_at} />
              </:col>
              <:expanded_content :let={revision}>
                <div data-part="revision-summary">
                  <.alert
                    status="information"
                    type="secondary"
                    size="large"
                    title={revision_summary_title(revision)}
                  >
                    <p>{revision_summary(
                      revision,
                      @spec.revisions,
                      @revision_summaries_enabled?
                    )}</p>
                  </.alert>
                </div>
              </:expanded_content>
            </.table>
          </.card_section>
        </.card>

        <.card icon="message_circle" title={dgettext("dashboard_specs", "Comments")}>
          <.card_section>
            <div :if={@spec.comments == []} data-part="empty-state">
              <h2>{dgettext("dashboard_specs", "No comments yet")}</h2>
              <p>
                {dgettext(
                  "dashboard_specs",
                  "Comments from contributors and members will appear here."
                )}
              </p>
            </div>

            <div :if={@spec.comments != []} data-part="comment-list">
              <article
                :for={comment <- @spec.comments}
                id={"comment-#{comment.id}"}
                data-part="comment"
              >
                <.avatar
                  id={"comment-avatar-#{comment.id}"}
                  name={comment_author(comment)}
                  image_href={avatar_url(comment.user)}
                  color={avatar_color(comment_author(comment))}
                  size="small"
                />
                <div data-part="comment-card">
                  <header data-part="comment-header">
                    <div data-part="comment-author">
                      <strong>{comment_author(comment)}</strong>
                      <span>{Calendar.strftime(comment.inserted_at, "%b %-d, %Y")}</span>
                      <.badge
                        :if={comment_new?(comment, @viewer_last_viewed_at)}
                        label={dgettext("dashboard_specs", "New")}
                        color="information"
                        style="light-fill"
                      />
                    </div>
                    <div data-part="comment-actions">
                      <button
                        :if={Specs.can_edit_comment?(comment, @current_user)}
                        type="button"
                        data-part="comment-action-button"
                        phx-click="edit_comment"
                        phx-value-id={comment.id}
                        aria-label={dgettext("dashboard_specs", "Edit comment")}
                        title={dgettext("dashboard_specs", "Edit comment")}
                      >
                        <.pencil />
                      </button>
                      <.modal
                        :if={Specs.can_edit_comment?(comment, @current_user)}
                        id={delete_comment_modal_id(comment.id)}
                        title={dgettext("dashboard_specs", "Delete comment?")}
                        description={dgettext("dashboard_specs", "This action cannot be undone.")}
                        header_type="warning"
                        header_size="large"
                      >
                        <:trigger :let={attrs}>
                          <button
                            type="button"
                            aria-label={dgettext("dashboard_specs", "Delete comment")}
                            title={dgettext("dashboard_specs", "Delete comment")}
                            {attrs}
                          >
                            <.trash />
                          </button>
                        </:trigger>
                        <.line_divider />
                        <.alert
                          status="warning"
                          type="secondary"
                          size="small"
                          title={
                            dgettext(
                              "dashboard_specs",
                              "Deleting this comment will permanently remove it from the spec discussion"
                            )
                          }
                        />
                        <.line_divider />
                        <:footer>
                          <.modal_footer>
                            <:action>
                              <.button
                                type="button"
                                label={dgettext("dashboard_specs", "Cancel")}
                                variant="secondary"
                                size="medium"
                                phx-click="close_delete_comment"
                                phx-value-id={comment.id}
                              />
                            </:action>
                            <:action>
                              <.button
                                type="button"
                                label={dgettext("dashboard_specs", "Delete")}
                                variant="destructive"
                                size="medium"
                                phx-click="delete_comment"
                                phx-value-id={comment.id}
                              />
                            </:action>
                          </.modal_footer>
                        </:footer>
                      </.modal>
                      <a
                        href={"#comment-#{comment.id}"}
                        data-part="comment-permalink"
                        aria-label={dgettext("dashboard_specs", "Permalink to comment")}
                        title={dgettext("dashboard_specs", "Permalink to comment")}
                      >
                        <.icon name="link_icon" />
                      </a>
                    </div>
                  </header>
                  <.form
                    :if={@editing_comment_id == comment.id}
                    id={"spec-comment-edit-form-#{comment.id}"}
                    for={@edit_comment_form}
                    phx-change="validate_comment_edit"
                    phx-submit="update_comment"
                    data-part="comment-edit-form"
                  >
                    <input type="hidden" name="comment_id" value={comment.id} />
                    <MentionComponents.mention_text_area
                      field={@edit_comment_form[:body]}
                      mention_suggestions={@mention_suggestions}
                      label={dgettext("dashboard_specs", "Edit comment")}
                      placeholder={dgettext("dashboard_specs", "Update your comment with Markdown")}
                      max_length={20_000}
                      rows={5}
                      required={true}
                      show_required={true}
                    />
                    <div data-part="form-actions">
                      <.button
                        label={dgettext("dashboard_specs", "Cancel")}
                        size="medium"
                        variant="secondary"
                        type="button"
                        phx-click="cancel_comment_edit"
                      />
                      <.button
                        label={dgettext("dashboard_specs", "Save comment")}
                        size="medium"
                        variant="primary"
                      />
                    </div>
                  </.form>
                  <div :if={@editing_comment_id != comment.id} data-part="comment-body">
                    {Markdown.render(comment.body)}
                  </div>
                </div>
              </article>
            </div>

            <.alert
              :if={!@signed_in?}
              status="information"
              type="secondary"
              size="large"
              title={dgettext("dashboard_specs", "Sign in to comment")}
              data-part="comment-auth-required"
            >
              <p>{dgettext("dashboard_specs", "Comments are available to authenticated users.")}</p>
              <:action>
                <.button
                  label={dgettext("dashboard_specs", "Sign in")}
                  href={~p"/login?#{[return_to: @current_path]}"}
                  size="medium"
                  variant="secondary"
                />
              </:action>
            </.alert>

            <.form
              :if={@signed_in?}
              for={@comment_form}
              phx-submit="comment"
              data-part="comment-form"
            >
              <MentionComponents.mention_text_area
                field={@comment_form[:body]}
                mention_suggestions={@mention_suggestions}
                label={dgettext("dashboard_specs", "Comment")}
                placeholder={dgettext("dashboard_specs", "Add context or feedback with Markdown")}
                max_length={20_000}
                rows={5}
                required={true}
                show_required={true}
              />
              <div data-part="form-actions">
                <.button label={dgettext("dashboard_specs", "Comment")} size="medium" variant="primary" />
              </div>
            </.form>
          </.card_section>
        </.card>
      </div>
    </section>
    """
  end

  attr :form, :any, required: true
  attr :title, :string, required: true
  attr :action_label, :string, required: true
  attr :projects, :list, required: true
  attr :domains, :list, required: true
  attr :source, :map, default: nil

  def spec_form(assigns) do
    ~H"""
    <section id="specs">
      <div data-part="header">
        <div data-part="title-group">
          <h1>{@title}</h1>
          <p>
            {if @source,
              do: dgettext("dashboard_specs", "Source: %{title}", title: @source.title),
              else: dgettext("dashboard_specs", "Write a proposal directly.")}
          </p>
        </div>
        <.button
          label={dgettext("dashboard_specs", "Back")}
          href={~p"/specs"}
          size="medium"
          variant="secondary"
        >
          <:icon_left><.arrow_left /></:icon_left>
        </.button>
      </div>

      <.card icon="file_text" title={dgettext("dashboard_specs", "Proposal")}>
        <.card_section>
          <.form id="spec-form" for={@form} phx-change="validate" phx-submit="save" data-part="form">
            <.text_input
              field={@form[:title]}
              label={dgettext("dashboard_specs", "Title")}
              placeholder={dgettext("dashboard_specs", "Describe the proposal in one sentence")}
              required={true}
              show_required={true}
            />
            <.text_area
              field={@form[:body]}
              label={dgettext("dashboard_specs", "Body")}
              placeholder={
                dgettext(
                  "dashboard_specs",
                  "Describe the problem, proposal, tradeoffs, and acceptance criteria with Markdown."
                )
              }
              max_length={100_000}
              rows={14}
              required={true}
              show_required={true}
            />
            <.project_select form={@form} projects={@projects} id="spec-project" />
            <.status_select form={@form} id="spec-status" />
            <.visibility_override_select form={@form} id="spec-visibility-override" />
            <fieldset data-part="checkbox-group">
              <legend>{dgettext("dashboard_specs", "Domains")}</legend>
              <input type="hidden" name="spec[domain_ids][]" value="" />
              <label :for={domain <- @domains} data-part="checkbox-option">
                <input
                  type="checkbox"
                  name="spec[domain_ids][]"
                  value={domain.id}
                  checked={domain_selected?(@form, domain.id)}
                />
                <span>{domain.name}</span>
              </label>
              <p :if={@domains == []}>
                {dgettext("dashboard_specs", "Create domains before linking them to specs.")}
              </p>
            </fieldset>
            <input
              :if={@form[:source_feature_request_id].value}
              type="hidden"
              name={@form[:source_feature_request_id].name}
              value={@form[:source_feature_request_id].value}
            />
            <input
              :if={@form[:lock_version].value}
              type="hidden"
              name={@form[:lock_version].name}
              value={@form[:lock_version].value}
            />
            <div data-part="form-actions">
              <.button label={@action_label} size="medium" variant="primary" />
            </div>
          </.form>
        </.card_section>
      </.card>
    </section>
    """
  end

  defp source_label(%{source_feature_request: %{title: title}}),
    do: dgettext("dashboard_specs", "Source: %{title}", title: title)

  defp source_label(_spec), do: dgettext("dashboard_specs", "Created directly")

  defp project_label(%{project: %{name: name}}) when is_binary(name), do: name
  defp project_label(_spec), do: dgettext("dashboard_specs", "No project")

  defp new_activity_since_visit?(%{viewer_last_viewed_at: nil}), do: false

  defp new_activity_since_visit?(%{viewer_last_viewed_at: viewed_at, spec: spec}) do
    DateTime.compare(spec.updated_at, viewed_at) == :gt or
      Enum.any?(comments(spec), &comment_new?(&1, viewed_at))
  end

  defp comments(%{comments: %Ecto.Association.NotLoaded{}}), do: []
  defp comments(%{comments: comments}) when is_list(comments), do: comments
  defp comments(_spec), do: []

  defp comment_new?(_comment, nil), do: false

  defp comment_new?(%{inserted_at: inserted_at}, viewed_at)
       when not is_nil(inserted_at) do
    DateTime.compare(inserted_at, viewed_at) == :gt
  end

  defp comment_new?(_comment, _viewed_at), do: false

  attr :spec, :map, required: true

  defp status_menu(assigns) do
    ~H"""
    <.dropdown
      id={"spec-status-menu-#{@spec.id}"}
      label={status_label(@spec.status)}
      size="medium"
      data-part="status-menu"
    >
      <.dropdown_item
        :for={status <- Spec.statuses()}
        value={Atom.to_string(status)}
        label={status_label(status)}
        size="large"
        on_click="set_status"
        phx-value-status={Atom.to_string(status)}
        data-selected={status == @spec.status}
      >
        <:right_icon :if={status == @spec.status}>
          <.check />
        </:right_icon>
      </.dropdown_item>
    </.dropdown>
    """
  end

  attr :form, :any, required: true
  attr :id, :string, required: true

  defp status_select(assigns) do
    assigns =
      assign(
        assigns,
        :value,
        Phoenix.HTML.Form.normalize_value("select", assigns.form[:status].value)
      )

    ~H"""
    <div data-part="select-field">
      <span>{dgettext("dashboard_specs", "Status")}</span>
      <.select
        id={@id}
        name={@form[:status].name}
        value={@value}
        label={dgettext("dashboard_specs", "Choose status")}
      >
        <:item
          :for={status <- Spec.statuses()}
          value={Atom.to_string(status)}
          label={status_label(status)}
        />
      </.select>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :projects, :list, required: true
  attr :id, :string, required: true

  defp project_select(assigns) do
    assigns =
      assign(
        assigns,
        :value,
        Phoenix.HTML.Form.normalize_value("select", assigns.form[:project_id].value)
      )

    ~H"""
    <div data-part="select-field">
      <span>{dgettext("dashboard_specs", "Project")}</span>
      <.select
        id={@id}
        name={@form[:project_id].name}
        value={@value}
        label={dgettext("dashboard_specs", "Choose project")}
      >
        <:item
          :for={project <- @projects}
          value={project.id}
          label={project.name}
          icon={project_icon(project)}
        />
      </.select>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :id, :string, required: true

  defp visibility_override_select(assigns) do
    assigns =
      assign(
        assigns,
        :value,
        Phoenix.HTML.Form.normalize_value("select", assigns.form[:visibility_override].value)
      )

    ~H"""
    <div data-part="select-field">
      <span>{dgettext("dashboard_specs", "Visibility")}</span>
      <.select
        id={@id}
        name={@form[:visibility_override].name}
        value={@value}
        label={dgettext("dashboard_specs", "Choose visibility")}
      >
        <:item value="" label={dgettext("dashboard_specs", "Inherit from project")} icon="git_branch" />
        <:item value="private" label={dgettext("dashboard_specs", "Private")} icon="lock" />
      </.select>
    </div>
    """
  end

  defp visibility_label(:private), do: dgettext("dashboard_specs", "Private")
  defp visibility_label(_visibility), do: dgettext("dashboard_specs", "Public")

  defp project_icon(%{visibility: :private}), do: "lock"
  defp project_icon(_project), do: "world"

  defp spec_domains(%{domains: %Ecto.Association.NotLoaded{}}), do: []
  defp spec_domains(%{domains: domains}) when is_list(domains), do: domains
  defp spec_domains(_spec), do: []

  defp domain_selected?(form, domain_id) do
    form[:domain_ids].value
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.member?(domain_id)
  end

  defp spec_number(%{number: number}) when is_integer(number), do: "##{number}"
  defp spec_number(_spec), do: "#?"

  defp status_label(:draft), do: dgettext("dashboard_specs", "Draft")
  defp status_label(:proposed), do: dgettext("dashboard_specs", "Proposed")
  defp status_label(:approved), do: dgettext("dashboard_specs", "Approved")
  defp status_label(:paused), do: dgettext("dashboard_specs", "Paused")
  defp status_label(:rejected), do: dgettext("dashboard_specs", "Rejected")
  defp status_label(:in_progress), do: dgettext("dashboard_specs", "In progress")
  defp status_label(:shipped), do: dgettext("dashboard_specs", "Shipped")
  defp status_label(:archived), do: dgettext("dashboard_specs", "Archived")

  defp status_label(status),
    do: status |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp status_color(:draft), do: "neutral"
  defp status_color(:proposed), do: "information"
  defp status_color(:approved), do: "success"
  defp status_color(:paused), do: "attention"
  defp status_color(:rejected), do: "destructive"
  defp status_color(:in_progress), do: "attention"
  defp status_color(:shipped), do: "success"
  defp status_color(:archived), do: "neutral"

  defp comment_author(%{user: %{email: email}}) when is_binary(email), do: email
  defp comment_author(%{author_name: name}) when is_binary(name), do: name
  defp comment_author(_comment), do: dgettext("dashboard_specs", "Anonymous")

  defp delete_comment_modal_id(comment_id), do: "delete-comment-modal-#{comment_id}"

  defp revision_author(%{user: %{email: email}}) when is_binary(email),
    do: dgettext("dashboard_specs", "Edited by %{email}", email: email)

  defp revision_author(_revision), do: dgettext("dashboard_specs", "Edited by an unknown user")

  defp revision_row_key(revision), do: "revision-#{revision.id}"

  defp revision_summary_title(%{revision: 1}), do: dgettext("dashboard_specs", "Initial draft")

  defp revision_summary_title(revision),
    do: dgettext("dashboard_specs", "Revision %{revision} summary", revision: revision.revision)

  defp revision_summary(%{summary: summary}, _revisions, _summaries_enabled?)
       when is_binary(summary) and summary != "",
       do: summary

  defp revision_summary(%{revision: 1, status: status}, _revisions, _summaries_enabled?) do
    dgettext("dashboard_specs", "Created the initial %{status} proposal.",
      status: String.downcase(status_label(status))
    )
  end

  defp revision_summary(_revision, _revisions, true) do
    dgettext("dashboard_specs", "The agent-written summary is not available yet.")
  end

  defp revision_summary(revision, revisions, false) do
    previous = Enum.find(revisions, &(&1.revision == revision.revision - 1))

    revision
    |> revision_changes(previous)
    |> humanize_revision_changes()
  end

  defp revision_changes(_revision, nil), do: []

  defp revision_changes(revision, previous) do
    [
      revision.title != previous.title && dgettext("dashboard_specs", "renamed the spec"),
      revision.status != previous.status &&
        dgettext("dashboard_specs", "moved the status from %{previous} to %{current}",
          previous: status_label(previous.status),
          current: status_label(revision.status)
        ),
      revision.body != previous.body && body_change_summary(previous.body, revision.body)
    ]
    |> Enum.reject(&(&1 in [false, nil]))
  end

  defp humanize_revision_changes([]),
    do: dgettext("dashboard_specs", "Saved the revision without changing the proposal text.")

  defp humanize_revision_changes([change]),
    do: dgettext("dashboard_specs", "This revision %{change}.", change: change)

  defp humanize_revision_changes(changes) do
    {last_change, previous_changes} = List.pop_at(changes, -1)

    dgettext("dashboard_specs", "This revision %{changes} and %{last_change}.",
      changes: Enum.join(previous_changes, ", "),
      last_change: last_change
    )
  end

  defp body_change_summary(previous_body, body) do
    previous_lines = meaningful_lines(previous_body)
    lines = meaningful_lines(body)

    diff = List.myers_difference(previous_lines, lines)
    added = diff |> Keyword.get_values(:ins) |> List.flatten() |> length()
    removed = diff |> Keyword.get_values(:del) |> List.flatten() |> length()

    cond do
      added > 0 and removed > 0 ->
        dgettext(
          "dashboard_specs",
          "updated the proposal body with %{added} and %{removed}",
          added: change_count(added, :addition),
          removed: change_count(removed, :removal)
        )

      added > 0 ->
        dgettext("dashboard_specs", "expanded the proposal body with %{count}",
          count: change_count(added, :addition)
        )

      removed > 0 ->
        dgettext("dashboard_specs", "trimmed the proposal body with %{count}",
          count: change_count(removed, :removal)
        )

      true ->
        dgettext("dashboard_specs", "updated the proposal body")
    end
  end

  defp meaningful_lines(nil), do: []

  defp meaningful_lines(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp change_count(1, :addition), do: dgettext("dashboard_specs", "1 addition")

  defp change_count(count, :addition),
    do: dgettext("dashboard_specs", "%{count} additions", count: count)

  defp change_count(1, :removal), do: dgettext("dashboard_specs", "1 removal")

  defp change_count(count, :removal),
    do: dgettext("dashboard_specs", "%{count} removals", count: count)

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
end
