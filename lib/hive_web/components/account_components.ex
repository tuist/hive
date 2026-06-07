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
      assigns
      |> assign(:linked_providers, linked_providers(assigns.identities))
      |> assign(:available_providers, available_providers(assigns.providers, assigns.identities))

    ~H"""
    <section id="account-identities">
      <div data-part="page-header">
        <div data-part="title-group">
          <.badge label="Account" color="information" style="light-fill" />
          <h1>Identities</h1>
          <p>Manage the sign-in providers connected to {@user.email}.</p>
        </div>
      </div>

      <.card icon="user" title="Connected identities" data-part="identities-card">
        <.card_section data-part="identities-section">
          <.table
            id="identities-table"
            rows={@identities}
            row_key={fn identity -> "identity-#{identity.provider}-#{identity.provider_uid}" end}
          >
            <:col :let={identity} label="Provider">
              <.text_and_description_cell
                icon={provider_icon(identity.provider)}
                label={provider_name(@providers, identity.provider)}
                description="Connected to this Hive user"
              />
            </:col>
            <:col :let={identity} label="Provider user ID">
              <.text_cell label={identity.provider_uid} data-provider-uid />
            </:col>
            <:empty_state>
              <.table_empty_state
                icon="user"
                title="No identities connected"
                subtitle="Sign in with an identity provider to connect it to this account."
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>

      <.card icon="link_icon" title="Available providers" data-part="providers-card">
        <.card_section data-part="providers-section">
          <div data-part="provider-list">
            <div :for={{key, meta} <- @providers} data-part="provider-row">
              <div data-part="provider-cell">
                <span data-part="provider-icon">
                  <.icon name={provider_icon(Atom.to_string(key))} />
                </span>
                <div data-part="provider-main">
                  <span data-part="provider-name">{meta.display_name}</span>
                  <span data-part="provider-state">
                    {if MapSet.member?(@linked_providers, Atom.to_string(key)),
                      do: "Connected",
                      else: "Not connected"}
                  </span>
                </div>
              </div>
              <.button
                :if={!MapSet.member?(@linked_providers, Atom.to_string(key))}
                label={"Connect #{meta.display_name}"}
                href={~p"/auth/#{key}"}
                variant="secondary"
                size="medium"
              />
              <.badge
                :if={MapSet.member?(@linked_providers, Atom.to_string(key))}
                label="Connected"
                color="success"
                style="light-fill"
              />
            </div>
            <div :if={@available_providers == []} data-part="provider-message">
              Every configured provider is connected to this account.
            </div>
          </div>
        </.card_section>
      </.card>
    </section>
    """
  end

  defp linked_providers(identities) do
    identities
    |> Enum.map(& &1.provider)
    |> MapSet.new()
  end

  defp available_providers(providers, identities) do
    linked = linked_providers(identities)
    Enum.reject(providers, fn {key, _meta} -> MapSet.member?(linked, Atom.to_string(key)) end)
  end

  defp provider_name(providers, provider) do
    providers
    |> Enum.find_value(default_provider_name(provider), fn {key, meta} ->
      if Atom.to_string(key) == provider, do: meta.display_name
    end)
  end

  defp provider_icon("github"), do: "brand_github"
  defp provider_icon("google"), do: "brand_google"
  defp provider_icon("okta"), do: "brand_okta"
  defp provider_icon(_provider), do: "user"

  defp default_provider_name("github"), do: "GitHub"
  defp default_provider_name("google"), do: "Google"
  defp default_provider_name("okta"), do: "Okta"

  defp default_provider_name(provider) do
    provider
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
