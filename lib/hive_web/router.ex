defmodule HiveWeb.Router do
  use HiveWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HiveWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug HiveWeb.Plugs.FetchCurrentUser
  end

  pipeline :require_auth do
    plug HiveWeb.Plugs.RequireAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", HiveWeb do
    pipe_through [:api]

    post "/slack/events", SlackEventsController, :handle
    post "/github/events", GitHubEventsController, :handle
  end

  scope "/", HiveWeb do
    pipe_through [:browser]

    live "/login", LoginLive, :login
    post "/dev/login", AuthController, :dev_login
  end

  scope "/auth", HiveWeb do
    pipe_through [:browser]

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/", HiveWeb do
    pipe_through [:browser]

    live_session :dashboard,
      on_mount: [{HiveWeb.LayoutLive, :default}],
      layout: {HiveWeb.Layouts, :dashboard} do
      live "/", SignalsLive, :index
      live "/signals", SignalsLive, :index
      live "/signals/:id", SignalLive, :show
      live "/swarms", SwarmsLive, :index
    end
  end

  scope "/", HiveWeb do
    pipe_through [:browser, :require_auth]

    live_session :settings,
      on_mount: [{HiveWeb.LayoutLive, :default}],
      layout: {HiveWeb.Layouts, :dashboard} do
      live "/settings", SettingsLive, :index
      live "/settings/signal-sources", SettingsSignalSourcesLive, :index
      live "/settings/signal-sources/slack/:id", SettingsSlackBotLive, :show
      live "/settings/signal-sources/github/:id", SettingsGitHubAppLive, :show
    end

    delete "/logout", AuthController, :delete
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:hive, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HiveWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
