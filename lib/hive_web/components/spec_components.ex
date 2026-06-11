defmodule HiveWeb.SpecComponents do
  @moduledoc false

  use HiveWeb, :html

  alias Hive.Specs
  alias Hive.Specs.Spec
  alias HiveWeb.Markdown

  attr :specs, :list, required: true
  attr :can_create?, :boolean, required: true
  attr :available_filters, :list, required: true
  attr :active_filters, :list, required: true

  def index(assigns) do
    ~H"""
    <section id="specs">
      <div data-part="header">
        <div data-part="title-group">
          <.badge label="Specs" color="information" style="light-fill" />
          <h1>Specs</h1>
          <p>Editable proposals that shape forage into buildable work.</p>
        </div>
        <.button
          :if={@can_create?}
          label="New spec"
          href={~p"/specs/new"}
          size="medium"
          variant="primary"
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </div>

      <.card icon="file_text" title="Specs">
        <.card_section>
          <div data-part="table-toolbar">
            <.filter_dropdown
              id="specs-filter"
              label="Filter"
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
            <h2>No specs yet</h2>
            <p>Specs that match the active filters will appear here.</p>
          </div>

          <.table
            :if={@specs != []}
            id="specs-table"
            rows={@specs}
            row_navigate={fn spec -> ~p"/specs/#{spec.number}" end}
          >
            <:col :let={spec} label="Spec">
              <div data-part="spec-table-cell">
                <.icon name="file_text" />
                <div data-part="spec-table-copy">
                  <strong>{spec_number(spec)} {spec.title}</strong>
                  <p>{visibility_label(Specs.effective_visibility(spec))} · {preview(spec.body)}</p>
                </div>
              </div>
            </:col>
            <:col :let={spec} label="Source">
              <span data-part="spec-table-source">{source_label(spec)}</span>
            </:col>
            <:col :let={spec} label="Products">
              <div data-part="spec-table-products">
                <.badge
                  :for={product <- spec_products(spec)}
                  label={product.name}
                  color="neutral"
                  style="light-fill"
                  size="large"
                />
                <span :if={spec_products(spec) == []} data-part="empty-products">
                  No products
                </span>
              </div>
            </:col>
            <:col :let={spec} label="Status">
              <.badge_cell
                label={status_label(spec.status)}
                color={status_color(spec.status)}
                style="light-fill"
              />
            </:col>
            <:col :let={spec} label="Updated">
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
  attr :can_edit?, :boolean, required: true
  attr :signed_in?, :boolean, required: true
  attr :user_name, :string, required: true
  attr :expanded_revision_rows, :list, required: true

  def show(assigns) do
    ~H"""
    <section id="specs">
      <div data-part="header">
        <div data-part="title-group">
          <.badge label={"Spec #{spec_number(@spec)}"} color="information" style="light-fill" />
          <h1>{@spec.title}</h1>
          <p>{visibility_label(Specs.effective_visibility(@spec))} · {source_label(@spec)}</p>
          <div :if={spec_products(@spec) != []} data-part="product-list">
            <.badge
              :for={product <- spec_products(@spec)}
              label={product.name}
              color="neutral"
              style="light-fill"
            />
          </div>
        </div>
        <div data-part="header-actions">
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
            label="Edit"
            href={~p"/specs/#{@spec.number}/edit"}
            size="medium"
            variant="primary"
          >
            <:icon_left><.pencil /></:icon_left>
          </.button>
        </div>
      </div>

      <div data-part="detail-stack">
        <.card icon="file_text" title="Proposal">
          <.card_section>
            <div data-part="spec-body">
              {Markdown.render(@spec.body)}
            </div>
          </.card_section>
        </.card>

        <.card icon="git_branch" title="Draft history">
          <.card_section>
            <.table
              id="spec-revisions-table"
              rows={@spec.revisions}
              row_key={&revision_row_key/1}
              row_expandable={fn _revision -> true end}
              expanded_rows={@expanded_revision_rows}
            >
              <:col :let={revision} label="Revision">
                <.text_cell
                  label={"Revision #{revision.revision}"}
                  sublabel={revision_author(revision)}
                  icon="git_commit"
                />
              </:col>
              <:col :let={revision} label="Status">
                <.badge_cell
                  label={status_label(revision.status)}
                  color={status_color(revision.status)}
                  style="light-fill"
                />
              </:col>
              <:col :let={revision} label="Edited">
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
                    <p>{revision_summary(revision, @spec.revisions)}</p>
                  </.alert>
                </div>
              </:expanded_content>
            </.table>
          </.card_section>
        </.card>

        <.card icon="message_circle" title="Comments">
          <.card_section>
            <div :if={@spec.comments == []} data-part="empty-state">
              <h2>No comments yet</h2>
              <p>Comments from contributors and members will appear here.</p>
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
                    </div>
                    <a
                      href={"#comment-#{comment.id}"}
                      data-part="comment-permalink"
                      aria-label="Permalink to comment"
                    >
                      <.icon name="link_icon" />
                    </a>
                  </header>
                  <div data-part="comment-body">{Markdown.render(comment.body)}</div>
                </div>
              </article>
            </div>

            <.alert
              :if={!@signed_in?}
              status="information"
              type="secondary"
              size="large"
              title="Sign in to comment"
              data-part="comment-auth-required"
            >
              <p>Comments are available to authenticated users.</p>
              <:action>
                <.button label="Sign in" href={~p"/login"} size="medium" variant="secondary" />
              </:action>
            </.alert>

            <.form
              :if={@signed_in?}
              for={@comment_form}
              phx-submit="comment"
              data-part="comment-form"
            >
              <.text_area
                field={@comment_form[:body]}
                label="Comment"
                placeholder="Add context or feedback with Markdown"
                max_length={4_000}
                rows={5}
                required={true}
                show_required={true}
              />
              <div data-part="form-actions">
                <.button label="Comment" size="medium" variant="primary" />
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
  attr :products, :list, required: true
  attr :source, :map, default: nil

  def spec_form(assigns) do
    ~H"""
    <section id="specs">
      <div data-part="header">
        <div data-part="title-group">
          <.badge label="Spec" color="information" style="light-fill" />
          <h1>{@title}</h1>
          <p>{if @source, do: "Source: #{@source.title}", else: "Write a proposal directly."}</p>
        </div>
        <.button label="Back" href={~p"/specs"} size="medium" variant="secondary">
          <:icon_left><.arrow_left /></:icon_left>
        </.button>
      </div>

      <.card icon="file_text" title="Proposal">
        <.card_section>
          <.form for={@form} phx-change="validate" phx-submit="save" data-part="form">
            <.text_input
              field={@form[:title]}
              label="Title"
              placeholder="Describe the proposal in one sentence"
              required={true}
              show_required={true}
            />
            <.text_area
              field={@form[:body]}
              label="Body"
              placeholder="Describe the problem, proposal, tradeoffs, and acceptance criteria with Markdown."
              max_length={20_000}
              rows={14}
              required={true}
              show_required={true}
            />
            <.status_select form={@form} id="spec-status" />
            <.visibility_select form={@form} id="spec-visibility" />
            <fieldset data-part="checkbox-group">
              <legend>Products</legend>
              <input type="hidden" name="spec[product_ids][]" value="" />
              <label :for={product <- @products} data-part="checkbox-option">
                <input
                  type="checkbox"
                  name="spec[product_ids][]"
                  value={product.id}
                  checked={product_selected?(@form, product.id)}
                />
                <span>{product.name}</span>
              </label>
              <p :if={@products == []}>Create products in Settings before linking them to specs.</p>
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

  defp preview(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 180)
  end

  defp source_label(%{source_feature_request: %{title: title}}), do: "Source: #{title}"
  defp source_label(_spec), do: "Created directly"

  attr :spec, :map, required: true

  defp status_menu(assigns) do
    ~H"""
    <.dropdown
      id={"spec-status-menu-#{@spec.id}"}
      label={status_label(@spec.status)}
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
      <span>Status</span>
      <.select id={@id} name={@form[:status].name} value={@value} label="Choose status">
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
  attr :id, :string, required: true

  defp visibility_select(assigns) do
    assigns =
      assign(
        assigns,
        :value,
        Phoenix.HTML.Form.normalize_value("select", assigns.form[:visibility].value)
      )

    ~H"""
    <div data-part="select-field">
      <span>Visibility</span>
      <.select id={@id} name={@form[:visibility].name} value={@value} label="Choose visibility">
        <:item
          :for={visibility <- Spec.visibilities()}
          value={Atom.to_string(visibility)}
          label={visibility_label(visibility)}
          icon={visibility_icon(visibility)}
        />
      </.select>
    </div>
    """
  end

  defp visibility_label(:private), do: "Private"
  defp visibility_label(_visibility), do: "Public"

  defp visibility_icon(:private), do: "lock"
  defp visibility_icon(_visibility), do: "world"

  defp spec_products(%{products: %Ecto.Association.NotLoaded{}}), do: []
  defp spec_products(%{products: products}) when is_list(products), do: products
  defp spec_products(_spec), do: []

  defp product_selected?(form, product_id) do
    form[:product_ids].value
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.member?(product_id)
  end

  defp spec_number(%{number: number}) when is_integer(number), do: "##{number}"
  defp spec_number(_spec), do: "#?"

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
  defp comment_author(_comment), do: "Anonymous"

  defp revision_author(%{user: %{email: email}}) when is_binary(email), do: "Edited by #{email}"
  defp revision_author(_revision), do: "Edited by an unknown user"

  defp revision_row_key(revision), do: "revision-#{revision.id}"

  defp revision_summary_title(%{revision: 1}), do: "Initial draft"
  defp revision_summary_title(revision), do: "Revision #{revision.revision} summary"

  defp revision_summary(%{revision: 1, status: status}, _revisions) do
    "Created the initial #{String.downcase(status_label(status))} proposal."
  end

  defp revision_summary(revision, revisions) do
    previous = Enum.find(revisions, &(&1.revision == revision.revision - 1))

    revision
    |> revision_changes(previous)
    |> humanize_revision_changes()
  end

  defp revision_changes(_revision, nil), do: []

  defp revision_changes(revision, previous) do
    [
      revision.title != previous.title && "renamed the spec",
      revision.status != previous.status &&
        "moved the status from #{status_label(previous.status)} to #{status_label(revision.status)}",
      revision.body != previous.body && body_change_summary(previous.body, revision.body)
    ]
    |> Enum.reject(&(&1 in [false, nil]))
  end

  defp humanize_revision_changes([]), do: "Saved the revision without changing the proposal text."
  defp humanize_revision_changes([change]), do: "This revision #{change}."

  defp humanize_revision_changes(changes) do
    {last_change, previous_changes} = List.pop_at(changes, -1)
    "This revision #{Enum.join(previous_changes, ", ")} and #{last_change}."
  end

  defp body_change_summary(previous_body, body) do
    previous_lines = meaningful_lines(previous_body)
    lines = meaningful_lines(body)

    diff = List.myers_difference(previous_lines, lines)
    added = diff |> Keyword.get_values(:ins) |> List.flatten() |> length()
    removed = diff |> Keyword.get_values(:del) |> List.flatten() |> length()

    cond do
      added > 0 and removed > 0 ->
        "updated the proposal body with #{change_count(added, "addition")} and #{change_count(removed, "removal")}"

      added > 0 ->
        "expanded the proposal body with #{change_count(added, "addition")}"

      removed > 0 ->
        "trimmed the proposal body with #{change_count(removed, "removal")}"

      true ->
        "updated the proposal body"
    end
  end

  defp meaningful_lines(nil), do: []

  defp meaningful_lines(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp change_count(1, singular), do: "1 #{singular}"
  defp change_count(count, singular), do: "#{count} #{singular}s"

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
