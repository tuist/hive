defmodule HiveWeb.AccountComponents do
  @moduledoc """
  Presentational components for account pages.
  """

  use HiveWeb, :html

  attr :user, :any, required: true
  attr :providers, :list, required: true
  attr :identities, :list, required: true

  def identities(assigns) do
    assigns =
      assign(assigns, :provider_options, provider_options(assigns.providers, assigns.identities))

    ~H"""
    <section id="account-identities">
      <div data-part="page-header">
        <div data-part="title-group">
          <.badge label="Account" color="information" style="light-fill" />
          <h1>Identities</h1>
          <p>
            Manage the sign-in providers connected to {@user.email}. Any connected provider can be used to access this account.
          </p>
        </div>
      </div>

      <.card icon="user" title="Sign-in providers" data-part="providers-card">
        <.card_section data-part="providers-section">
          <div data-part="providers-table">
            <.table
              id="identities-table"
              rows={@provider_options}
              row_key={fn option -> "provider-#{option.key}" end}
            >
              <:col :let={option} label="Provider">
                <.text_and_description_cell
                  icon={provider_icon(option.key)}
                  label={option.display_name}
                  description={provider_description(option)}
                  data-state={provider_state(option)}
                />
              </:col>
              <:col :let={option} label="Account">
                <.text_cell label={if option.connected?, do: option.uid, else: "—"} data-provider-uid />
              </:col>
              <:col :let={option} label="Status">
                <.badge_cell
                  :if={option.connected?}
                  label="Connected"
                  color="success"
                  style="light-fill"
                />
                <.button_cell :if={option.configured? and not option.connected?}>
                  <:button>
                    <.button
                      label={"Connect #{option.display_name}"}
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
                  label="Not configured"
                  color="neutral"
                  style="light-fill"
                />
              </:col>
            </.table>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

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

  defp provider_description(%{connected?: true}), do: "Connected to this account"

  defp provider_description(%{configured?: true} = option),
    do: "Use your #{option.display_name} account to sign in to Hive"

  defp provider_description(%{key: "github"}),
    do: "GitHub sign-in is not enabled for this Hive instance"

  defp provider_description(_option), do: "Not enabled for this Hive instance"

  defp default_provider_name("github"), do: "GitHub"
  defp default_provider_name("google"), do: "Google"
  defp default_provider_name("okta"), do: "Okta"

  defp default_provider_name(provider) do
    provider
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
