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

    pipe_through :browser

    get "/login", AuthController, :new
    post "/logout", AuthController, :delete

    if Application.compile_env(:hive, :dev_routes, false) do
      post "/dev/login", AuthController, :dev_login
    end

    get "/forage/feature-requests", ForageController, :feature_requests
    get "/forage/feature-requests/new", ForageController, :new_feature_request
    post "/forage/feature-requests", ForageController, :create_feature_request
    get "/forage/bug-reports", ForageController, :bug_reports
    get "/forage/feedback", ForageController, :feedback
    get "/forage/grafana-alerts", ForageController, :grafana_alerts

    scope "/auth" do
      pipe_through :oauth
      get "/:provider", AuthController, :request
      get "/:provider/callback", AuthController, :callback
    end

    pipe_through HiveWeb.Plugs.RequireAuthenticated

    get "/", PageController, :home
  end
end
