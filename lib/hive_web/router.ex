defmodule HiveWeb.Router do
  use HiveWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :oauth do
    plug Ueberauth
  end

  scope "/", HiveWeb do
    get "/ready", HealthController, :ready
    get "/open-graph/:page_id/:hash", OpenGraphController, :show

    pipe_through :browser

    get "/login", AuthController, :new
    post "/logout", AuthController, :delete

    if Application.compile_env(:hive, :dev_routes, false) do
      post "/dev/login", AuthController, :dev_login
    end

    live_session :forage,
      on_mount: HiveWeb.ForageLive.Hooks,
      root_layout: {HiveWeb.Layouts, :root} do
      live "/forage/feature-requests", ForageLive.FeatureRequests
      live "/forage/feature-requests/new", ForageLive.NewFeatureRequest
      live "/forage/bug-reports", ForageLive.Placeholder, :bug_reports
      live "/forage/feedback", ForageLive.Placeholder, :feedback
      live "/forage/grafana-alerts", ForageLive.Placeholder, :grafana_alerts
    end

    scope "/auth" do
      pipe_through :oauth
      get "/:provider", AuthController, :request
      get "/:provider/callback", AuthController, :callback
    end

    pipe_through HiveWeb.Plugs.RequireAuthenticated

    get "/", PageController, :home
  end
end
