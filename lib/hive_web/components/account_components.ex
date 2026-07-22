defmodule HiveWeb.AccountComponents do
  @moduledoc """
  Presentational components for account pages.
  """

  use HiveWeb, :html

  alias HiveWeb.Utilities.Query

  attr :user, :any, required: true
  attr :providers, :list, required: true
  attr :identities, :list, required: true
  attr :slack_enabled?, :boolean, default: false
  attr :slack_profiles, :list, default: []

  def identities(assigns) do
    assigns =
      assign(assigns, :provider_options, provider_options(assigns.providers, assigns.identities))

    ~H"""
    <section id="account-identities">
      <div data-part="page-header">
        <div data-part="title-group">
          <h1>{dgettext("dashboard_account", "Identities")}</h1>
          <p>
            {dgettext(
              "dashboard_account",
              "Manage the sign-in providers connected to %{email}. Any connected provider can be used to access this account.",
              email: @user.email
            )}
          </p>
        </div>
      </div>

      <.card
        icon="user"
        title={dgettext("dashboard_account", "Sign-in providers")}
        data-part="providers-card"
      >
        <.card_section data-part="providers-section">
          <div data-part="providers-table">
            <.table
              id="identities-table"
              rows={@provider_options}
              row_key={fn option -> "provider-#{option.key}" end}
            >
              <:col :let={option} label={dgettext("dashboard_account", "Provider")}>
                <.text_and_description_cell
                  icon={provider_icon(option.key)}
                  label={option.display_name}
                  description={provider_description(option)}
                  data-state={provider_state(option)}
                />
              </:col>
              <:col :let={option} label={dgettext("dashboard_account", "Account")}>
                <.text_cell label={if option.connected?, do: option.uid, else: "—"} data-provider-uid />
              </:col>
              <:col :let={option} label={dgettext("dashboard_account", "Status")}>
                <.badge_cell
                  :if={option.connected?}
                  label={dgettext("dashboard_account", "Connected")}
                  color="success"
                  style="light-fill"
                />
                <.button_cell :if={option.configured? and not option.connected?}>
                  <:button>
                    <.button
                      label={
                        dgettext("dashboard_account", "Connect %{provider}",
                          provider: option.display_name
                        )
                      }
                      href={~p"/auth/#{option.key}"}
                      variant="secondary"
                      size="medium"
                    >
                      <:icon_left><.icon name="link_icon" /></:icon_left>
                    </.button>
                  </:button>
                </.button_cell>
                <.badge_cell
                  :if={not option.configured? and not option.connected?}
                  label={dgettext("dashboard_account", "Not configured")}
                  color="neutral"
                  style="light-fill"
                />
              </:col>
            </.table>
          </div>
        </.card_section>
      </.card>

      <.card
        icon="brand_slack"
        title={dgettext("dashboard_account", "Slack profile")}
        data-part="slack-card"
      >
        <:actions>
          <.button
            :if={@slack_enabled?}
            label={dgettext("dashboard_account", "Connect Slack profile")}
            href={~p"/account/slack/new"}
            variant="secondary"
            size="medium"
          >
            <:icon_left><.icon name="link_icon" /></:icon_left>
          </.button>
          <.badge
            :if={not @slack_enabled?}
            label={dgettext("dashboard_account", "Slack not configured")}
            color="neutral"
            style="light-fill"
          />
        </:actions>
        <.card_section data-part="slack-section">
          <div data-part="slack-copy">
            <p>
              {dgettext(
                "dashboard_account",
                "Connect your Slack profile so Hive can send targeted notifications instead of posting every update to a channel."
              )}
            </p>
          </div>

          <div data-part="slack-profiles-table">
            <.table
              id="slack-profiles-table"
              rows={@slack_profiles}
              row_key={fn profile -> "slack-profile-#{profile.id}" end}
            >
              <:col :let={profile} label={dgettext("dashboard_account", "Workspace")}>
                <.text_and_description_cell
                  icon="brand_slack"
                  label={profile.installation.team_name || profile.installation.team_id}
                  description={slack_profile_label(profile)}
                />
              </:col>
              <:col :let={_profile} label={dgettext("dashboard_account", "Status")}>
                <.badge_cell
                  label={dgettext("dashboard_account", "Connected")}
                  color="success"
                  style="light-fill"
                />
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="brand_slack"
                  title={dgettext("dashboard_account", "No Slack profile connected")}
                  subtitle={slack_empty_subtitle(@slack_enabled?)}
                />
              </:empty_state>
            </.table>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :email_enabled?, :boolean, required: true
  attr :global_preferences, :list, required: true
  attr :domains, :list, required: true
  attr :domain_preferences, :map, required: true
  attr :followed_items, :list, required: true
  attr :followed_items_meta, :map, required: true
  attr :available_filters, :list, required: true
  attr :active_filters, :list, required: true
  attr :search_form, :any, required: true
  attr :query, :string, required: true
  attr :uri, :any, required: true

  def notifications(assigns) do
    ~H"""
    <section id="account-notifications">
      <div data-part="page-header">
        <div data-part="title-group">
          <h1>{dgettext("dashboard_account", "Notifications")}</h1>
          <p>
            {dgettext(
              "dashboard_account",
              "Choose the updates Hive sends to your account email. Daily summaries are sent at 08:00 Coordinated Universal Time. You can also follow individual Forage items and specs from their pages."
            )}
          </p>
        </div>
        <.badge
          :if={not @email_enabled?}
          label={dgettext("dashboard_account", "Email delivery is not configured")}
          color="warning"
          style="light-fill"
        />
      </div>

      <.card icon="mail" title={dgettext("dashboard_account", "Activity")}>
        <.card_section>
          <div data-part="preference-list">
            <.notification_preference
              :for={preference <- @global_preferences}
              label={notification_topic_label(preference.topic)}
              description={notification_topic_description(preference.topic)}
              topic={preference.topic}
              cadence={preference.cadence}
              weekly?={preference.topic == :weekly_drop_digest}
            />
          </div>
        </.card_section>
      </.card>

      <.card icon="treemap" title={dgettext("dashboard_account", "Domain drops")}>
        <.card_section>
          <p data-part="section-copy">
            {dgettext(
              "dashboard_account",
              "Subscribe only to the domains whose shipped updates you want to follow."
            )}
          </p>
          <div data-part="domain-list">
            <div :for={domain <- @domains} data-part="preference-row">
              <div data-part="preference-copy">
                <.link navigate={~p"/domains/#{domain.id}"}>{domain.name}</.link>
                <span>{domain.description}</span>
              </div>
              <.cadence_buttons
                event="set_domain"
                id={domain.id}
                cadence={Map.get(@domain_preferences, domain.id)}
              />
            </div>
            <div :if={@domains == []} data-part="empty-state">
              <.icon name="treemap" />
              <strong>{dgettext("dashboard_account", "No domains available")}</strong>
              <span>{dgettext("dashboard_account", "Visible domains will appear here.")}</span>
            </div>
          </div>
        </.card_section>
      </.card>

      <.card icon="eye" title={dgettext("dashboard_account", "Following")}>
        <.card_section data-part="following-section">
          <p data-part="section-copy">
            {dgettext(
              "dashboard_account",
              "Creators and commenters automatically follow the conversation. You can change the timing or unfollow at any time."
            )}
          </p>
          <div data-part="following-table">
            <div data-part="table-toolbar">
              <.filter_dropdown
                id="notification-following-filter"
                label={dgettext("dashboard_account", "Filter")}
                available_filters={@available_filters}
                active_filters={@active_filters}
                on_select="add_filter"
              />

              <div data-part="search">
                <.form
                  id="notification-following-search-form"
                  for={@search_form}
                  phx-change="search"
                  phx-submit="search"
                >
                  <.text_input
                    id="notification-following-search"
                    field={@search_form[:query]}
                    type="search"
                    show_suffix={false}
                    placeholder={dgettext("dashboard_account", "Search followed items...")}
                  />
                </.form>
              </div>
            </div>

            <div :if={@active_filters != []} data-part="active-filters">
              <.active_filter :for={filter <- @active_filters} filter={filter} />
            </div>

            <.table
              id="notification-following-table"
              rows={@followed_items}
              row_key={fn item -> "following-#{item.topic}-#{item.id}" end}
            >
              <:col :let={item} label={dgettext("dashboard_account", "Item")}>
                <.link navigate={item.path} data-part="resource-link">
                  <.text_and_description_cell
                    icon={followed_item_icon(item.topic)}
                    label={item.title}
                    description={item.description}
                  />
                </.link>
              </:col>
              <:col :let={item} label={dgettext("dashboard_account", "Email delivery")}>
                <div data-part="cell" data-type="cadence">
                  <.cadence_buttons
                    event="set_follow"
                    topic={item.topic}
                    id={item.id}
                    cadence={item.cadence}
                  />
                </div>
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="eye"
                  title={
                    if @query != "" or @active_filters != [],
                      do: dgettext("dashboard_account", "No followed items found"),
                      else: dgettext("dashboard_account", "No followed items")
                  }
                  subtitle={
                    if @query != "" or @active_filters != [],
                      do:
                        dgettext(
                          "dashboard_account",
                          "Adjust the search or filter to find another followed item."
                        ),
                      else:
                        dgettext(
                          "dashboard_account",
                          "Follow a Forage item or spec to receive updates about its conversation and progress."
                        )
                  }
                />
              </:empty_state>
            </.table>

            <div :if={@followed_items_meta.total_pages > 1} data-part="pagination">
              <.button
                variant="secondary"
                label={dgettext("dashboard_account", "Prev")}
                disabled={@followed_items_meta.current_page <= 1}
                patch={
                  notification_page_link(@uri, max(1, @followed_items_meta.current_page - 1))
                }
              >
                <:icon_left><.chevron_left /></:icon_left>
              </.button>
              <.button
                variant="secondary"
                label={dgettext("dashboard_account", "Next")}
                disabled={@followed_items_meta.current_page >= @followed_items_meta.total_pages}
                patch={
                  notification_page_link(
                    @uri,
                    min(@followed_items_meta.total_pages, @followed_items_meta.current_page + 1)
                  )
                }
              >
                <:icon_right><.chevron_right /></:icon_right>
              </.button>
            </div>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :description, :string, required: true
  attr :topic, :atom, required: true
  attr :cadence, :atom, default: nil
  attr :weekly?, :boolean, default: false

  defp notification_preference(assigns) do
    ~H"""
    <div data-part="preference-row">
      <div data-part="preference-copy">
        <strong>{@label}</strong>
        <span>{@description}</span>
      </div>
      <.button_group size="medium" data-part="cadence-control">
        <.button_group_item
          label={dgettext("dashboard_account", "Off")}
          phx-click="set_global"
          phx-value-topic={@topic}
          phx-value-cadence="off"
          data-selected={is_nil(@cadence)}
          aria-pressed={to_string(is_nil(@cadence))}
        />
        <.button_group_item
          :if={not @weekly?}
          label={dgettext("dashboard_account", "Daily")}
          phx-click="set_global"
          phx-value-topic={@topic}
          phx-value-cadence="daily"
          data-selected={@cadence == :daily}
          aria-pressed={to_string(@cadence == :daily)}
        />
        <.button_group_item
          label={if @weekly?, do: dgettext("dashboard_account", "Every edition"), else: dgettext("dashboard_account", "Immediately")}
          phx-click="set_global"
          phx-value-topic={@topic}
          phx-value-cadence="immediate"
          data-selected={@cadence == :immediate}
          aria-pressed={to_string(@cadence == :immediate)}
        />
      </.button_group>
    </div>
    """
  end

  attr :event, :string, required: true
  attr :topic, :atom, default: nil
  attr :id, :string, required: true
  attr :cadence, :atom, default: nil

  defp cadence_buttons(assigns) do
    ~H"""
    <.button_group size="medium" data-part="cadence-control">
      <.button_group_item
        label={dgettext("dashboard_account", "Off")}
        phx-click={@event}
        phx-value-topic={@topic}
        phx-value-id={@id}
        phx-value-cadence="off"
        data-selected={is_nil(@cadence)}
        aria-pressed={to_string(is_nil(@cadence))}
      />
      <.button_group_item
        label={dgettext("dashboard_account", "Daily")}
        phx-click={@event}
        phx-value-topic={@topic}
        phx-value-id={@id}
        phx-value-cadence="daily"
        data-selected={@cadence == :daily}
        aria-pressed={to_string(@cadence == :daily)}
      />
      <.button_group_item
        label={dgettext("dashboard_account", "Immediately")}
        phx-click={@event}
        phx-value-topic={@topic}
        phx-value-id={@id}
        phx-value-cadence="immediate"
        data-selected={@cadence == :immediate}
        aria-pressed={to_string(@cadence == :immediate)}
      />
    </.button_group>
    """
  end

  defp followed_item_icon(:forage_item_updates), do: "rss"
  defp followed_item_icon(:spec_updates), do: "file_text"

  defp notification_page_link(uri, page) do
    "?" <> Query.put(uri.query, "page", Integer.to_string(page))
  end

  defp notification_topic_label(:forage_new_items),
    do: dgettext("dashboard_account", "New Forage items")

  defp notification_topic_label(:spec_new), do: dgettext("dashboard_account", "New specs")

  defp notification_topic_label(:weekly_drop_digest),
    do: dgettext("dashboard_account", "Weekly drop digest")

  defp notification_topic_description(:forage_new_items),
    do:
      dgettext(
        "dashboard_account",
        "New feature requests, feedback, issues, and alerts visible to you."
      )

  defp notification_topic_description(:spec_new),
    do: dgettext("dashboard_account", "New specs visible to you.")

  defp notification_topic_description(:weekly_drop_digest),
    do: dgettext("dashboard_account", "The published weekly summary of shipped updates.")

  defp slack_profile_label(profile) do
    cond do
      is_binary(profile.email) and profile.email != "" ->
        "#{profile.email} · #{profile.slack_user_id}"

      is_binary(profile.name) and profile.name != "" ->
        "#{profile.name} · #{profile.slack_user_id}"

      true ->
        profile.slack_user_id
    end
  end

  defp slack_empty_subtitle(true),
    do:
      dgettext(
        "dashboard_account",
        "Connect your Slack profile to receive targeted notifications."
      )

  defp slack_empty_subtitle(false),
    do:
      dgettext(
        "dashboard_account",
        "Slack profile linking is not enabled for this Hive instance."
      )

  defp provider_options(providers, identities) do
    uids = Map.new(identities, &{&1.provider, &1.provider_uid})

    providers
    |> Map.new(fn {key, meta} ->
      string_key = Atom.to_string(key)
      {string_key, %{key: string_key, display_name: meta.display_name, configured?: true}}
    end)
    |> then(fn configured ->
      Enum.reduce(identities, configured, fn identity, acc ->
        Map.put_new(acc, identity.provider, %{
          key: identity.provider,
          display_name: default_provider_name(identity.provider),
          configured?: false
        })
      end)
    end)
    |> Map.put_new("github", %{key: "github", display_name: "GitHub", configured?: false})
    |> Map.values()
    |> Enum.map(fn option ->
      uid = Map.get(uids, option.key)
      Map.merge(option, %{connected?: not is_nil(uid), uid: uid})
    end)
    |> Enum.sort_by(fn o -> {not o.connected?, not o.configured?, o.display_name} end)
  end

  defp provider_icon("github"), do: "brand_github"
  defp provider_icon("google"), do: "brand_google"
  defp provider_icon("okta"), do: "brand_okta"
  defp provider_icon(_provider), do: "user"

  defp provider_state(%{connected?: true}), do: "connected"
  defp provider_state(%{configured?: true}), do: "available"
  defp provider_state(_option), do: "unconfigured"

  defp provider_description(%{connected?: true}),
    do: dgettext("dashboard_account", "Connected to this account")

  defp provider_description(%{configured?: true} = option),
    do:
      dgettext("dashboard_account", "Use your %{provider} account to sign in to Hive",
        provider: option.display_name
      )

  defp provider_description(%{key: "github"}),
    do: dgettext("dashboard_account", "GitHub sign-in is not enabled for this Hive instance")

  defp provider_description(_option),
    do: dgettext("dashboard_account", "Not enabled for this Hive instance")

  defp default_provider_name("github"), do: "GitHub"
  defp default_provider_name("google"), do: "Google"
  defp default_provider_name("okta"), do: "Okta"

  defp default_provider_name(provider) do
    provider
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
