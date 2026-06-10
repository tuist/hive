defmodule HiveWeb.Router do
  use HiveWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :session do
    plug :fetch_session
  end

  pipeline :oauth do
    plug Ueberauth
  end

  pipeline :json_api do
    plug :accepts, ["json"]
  end

  pipeline :oauth_registration do
    plug HiveWeb.Plugs.OAuthRegistrationRateLimit
  end

  pipeline :mcp do
    plug HiveWeb.Plugs.MCPAuthentication
  end

  scope "/webhooks", HiveWeb do
    pipe_through :json_api

    post "/github", GitHubWebhookController, :create
  end

  scope "/", HiveWeb do
    get "/ready", HealthController, :ready

    scope "/" do
      pipe_through :session

      get "/open-graph/:page_id/:hash", OpenGraphController, :show
    end

    scope "/.well-known" do
      pipe_through :json_api

      get "/oauth-authorization-server", WellKnownController, :oauth_authorization_server
      get "/oauth-protected-resource", WellKnownController, :oauth_protected_resource

      get "/oauth-protected-resource/*resource_path",
          WellKnownController,
          :oauth_protected_resource

      get "/mcp/server-card.json", WellKnownController, :mcp_server_card
    end

    scope "/oauth2", OAuth do
      pipe_through [:json_api]

      post "/token", TokenController, :token
    end

    scope "/oauth2", OAuth do
      pipe_through [:json_api, :oauth_registration]

      post "/register", RegistrationController, :register
    end

    pipe_through :browser

    get "/login", AuthController, :new
    post "/logout", AuthController, :delete

    scope "/oauth2", OAuth do
      get "/authorize", AuthorizeController, :authorize
      post "/authorize", AuthorizeController, :approve
    end

    if Application.compile_env(:hive, :dev_routes, false) do
      post "/dev/login", AuthController, :dev_login
    end

    live_session :forage,
      on_mount: HiveWeb.DashboardLive.Hooks,
      root_layout: {HiveWeb.Layouts, :root} do
      live "/forage/feature-requests", ForageLive.FeatureRequests
      live "/forage/feature-requests/new", ForageLive.NewFeatureRequest
      live "/forage/bug-reports", ForageLive.Placeholder, :bug_reports
      live "/forage/feedback", ForageLive.Placeholder, :feedback
      live "/forage/grafana-alerts", ForageLive.Placeholder, :grafana_alerts
      live "/specs", SpecLive.Index
      live "/specs/new", SpecLive.New
      live "/specs/:number", SpecLive.Show
      live "/specs/:number/edit", SpecLive.Edit
    end

    live_session :settings,
      on_mount: HiveWeb.DashboardLive.Hooks,
      root_layout: {HiveWeb.Layouts, :root} do
      live "/settings/products", SettingsLive.Products
      live "/settings/products/:id", SettingsLive.Product
    end

    live_session :account,
      on_mount: HiveWeb.DashboardLive.Hooks,
      root_layout: {HiveWeb.Layouts, :root} do
      live "/account/identities", AccountLive.Identities
    end

    scope "/auth" do
      pipe_through :oauth
      get "/:provider", AuthController, :request
      get "/:provider/callback", AuthController, :callback
    end

    pipe_through HiveWeb.Plugs.RequireAuthenticated

    get "/", PageController, :home
  end

  scope "/" do
    pipe_through :mcp

    forward "/mcp", EMCP.Transport.StreamableHTTP, server: Hive.MCP.Server
  end
end
