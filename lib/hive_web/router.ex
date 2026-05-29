defmodule HiveWeb.Router do
  use HiveWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
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

    scope "/auth" do
      pipe_through :oauth
      get "/:provider", AuthController, :request
      get "/:provider/callback", AuthController, :callback
    end

    pipe_through HiveWeb.Plugs.RequireAuthenticated

    get "/", PageController, :home
  end
end
