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

  pipeline :feed do
    plug :accepts, ["xml"]
    plug :fetch_session
    plug HiveWeb.Plugs.RequireAuthenticated
  end

  pipeline :oauth_registration do
    plug HiveWeb.Plugs.OAuthRegistrationRateLimit
  end

  pipeline :mcp do
    plug HiveWeb.Plugs.MCPAuthentication
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug HiveWeb.Plugs.APIAuthentication
  end

  pipeline :inference do
    plug :accepts, ["json", "event-stream"]
    plug HiveWeb.Plugs.InferenceAuthentication
  end

  scope "/webhooks", HiveWeb do
    pipe_through :json_api

    post "/github", GitHubWebhookController, :create
    post "/projects/:project_id/:source/:token", ProjectWebhookController, :create
  end

  scope "/api/slack", HiveWeb do
    pipe_through :json_api

    post "/events", SlackController, :events
    post "/interactions", SlackController, :interactions
  end

  scope "/api", HiveWeb.API do
    pipe_through :api

    get "/flights", FlightController, :index
    get "/flights/:id", FlightController, :show
  end

  scope "/", HiveWeb do
    get "/live", HealthController, :live
    get "/ready", HealthController, :ready

    scope "/" do
      pipe_through :session

      get "/open-graph/card.jpg", OpenGraphController, :show
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

    scope "/" do
      pipe_through :feed

      get "/forage/atom.xml", FeedController, :forage_atom
      get "/forage/rss.xml", FeedController, :forage_rss
      get "/forage/feature-requests/atom.xml", FeedController, :feature_requests_atom
      get "/forage/feature-requests/rss.xml", FeedController, :feature_requests_rss
      get "/forage/github-issues/atom.xml", FeedController, :github_issues_atom
      get "/forage/github-issues/rss.xml", FeedController, :github_issues_rss
      get "/forage/grafana-alerts/atom.xml", FeedController, :grafana_alerts_atom
      get "/forage/grafana-alerts/rss.xml", FeedController, :grafana_alerts_rss
      get "/flights/atom.xml", FeedController, :flights_atom
      get "/flights/rss.xml", FeedController, :flights_rss
      get "/specs/atom.xml", FeedController, :specs_atom
      get "/specs/rss.xml", FeedController, :specs_rss
      get "/drops/atom.xml", FeedController, :drops_atom
      get "/drops/rss.xml", FeedController, :drops_rss
      get "/drops/digest/atom.xml", FeedController, :drops_digest_atom
      get "/drops/digest/rss.xml", FeedController, :drops_digest_rss
      get "/domains/:id/atom.xml", FeedController, :domain_atom
      get "/domains/:id/rss.xml", FeedController, :domain_rss
      get "/domains/:id/drops/atom.xml", FeedController, :domain_drops_atom
      get "/domains/:id/drops/rss.xml", FeedController, :domain_drops_rss
      get "/projects/:id/drops/atom.xml", FeedController, :project_drops_atom
      get "/projects/:id/drops/rss.xml", FeedController, :project_drops_rss
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

    get "/ops", PageController, :ops
    get "/audit", PageController, :audit

    live_session :forage,
      on_mount: HiveWeb.DashboardLive.Hooks,
      root_layout: {HiveWeb.Layouts, :root} do
      live "/forage", ForageLive.Index, :index
      live "/forage/new", ForageLive.NewFeatureRequest
      live "/forage/items/:origin/:id", ForageLive.Show
      live "/forage/feature-requests/new", ForageLive.NewFeatureRequest
      live "/forage/feature-requests", ForageLive.Index, :feature_requests
      live "/forage/bug-reports", ForageLive.Index, :bug_reports
      live "/forage/feedback", ForageLive.Index, :feedback
      live "/forage/github-issues", ForageLive.Index, :github_issues
      live "/forage/grafana-alerts", ForageLive.Index, :grafana_alerts
      live "/specs", SpecLive.Index
      live "/specs/new", SpecLive.New
      live "/specs/:number", SpecLive.Show
      live "/specs/:number/edit", SpecLive.Edit
      live "/drops", DropsLive.Index
      live "/drops/subscribe", DropsLive.Subscribe
      live "/drops/digest", DropsLive.Digest
      live "/drops/digest/:week", DropsLive.Digest
      live "/drops/:number", DropsLive.Show
    end

    live_session :flights,
      on_mount: HiveWeb.DashboardLive.Hooks,
      root_layout: {HiveWeb.Layouts, :root} do
      live "/flights", FlightLive.Index, :index
      live "/flights/:id", FlightLive.Show, :show
    end

    live_session :domains,
      on_mount: HiveWeb.DashboardLive.Hooks,
      root_layout: {HiveWeb.Layouts, :root} do
      live "/domains", DomainLive.Index
      live "/domains/:id", DomainLive.Show
    end

    live_session :projects,
      on_mount: HiveWeb.DashboardLive.Hooks,
      root_layout: {HiveWeb.Layouts, :root} do
      live "/projects", ProjectLive.Index
      live "/projects/:id", ProjectLive.Show
    end

    live_session :account,
      on_mount: HiveWeb.DashboardLive.Hooks,
      root_layout: {HiveWeb.Layouts, :root} do
      live "/account/identities", AccountLive.Identities
    end

    live_session :ops,
      on_mount: HiveWeb.DashboardLive.Hooks,
      root_layout: {HiveWeb.Layouts, :root} do
      live "/ops/slack", OpsLive.Slack
      live "/ops/drops", OpsLive.Drops
      live "/ops/forage", OpsLive.Forage
      live "/ops/inference", OpsLive.Inference
      live "/ops/inference/profiles", OpsLive.Inference
      live "/ops/inference/profiles/:id", OpsLive.InferenceProfile
      live "/ops/inference/providers", OpsLive.InferenceProviders
      live "/ops/inference/tokens/:id", OpsLive.InferenceToken
      live "/ops/audit", AuditLive
    end

    scope "/slack" do
      pipe_through HiveWeb.Plugs.RequireAuthenticated

      get "/install", SlackInstallController, :new
      get "/install/callback", SlackInstallController, :callback
      post "/installations/:id/disconnect", SlackInstallController, :disconnect
    end

    scope "/account/slack" do
      pipe_through HiveWeb.Plugs.RequireAuthenticated

      get "/new", SlackProfileController, :new
      get "/callback", SlackProfileController, :callback
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

    forward "/mcp", Hive.MCP.Transport.StreamableHTTP, server: Hive.MCP.Server
  end

  scope "/inference/v1", HiveWeb do
    pipe_through :inference

    get "/models", InferenceController, :models
    post "/chat/completions", InferenceController, :chat_completions
    post "/embeddings", InferenceController, :embeddings
  end
end
