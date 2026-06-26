defmodule HiveWeb.AccountComponents do
  @moduledoc """
  Presentational components for account pages.
  """

  use HiveWeb, :html

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
