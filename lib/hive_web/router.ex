defmodule HiveWeb.Router do
  use HiveWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", HiveWeb do
    get "/ready", HealthController, :ready

    pipe_through :browser

    get "/login", AuthController, :new
    get "/auth/oidc", AuthController, :oidc
    get "/auth/oidc/callback", AuthController, :callback
    post "/logout", AuthController, :delete

    pipe_through HiveWeb.Plugs.RequireAuthenticated

    get "/", PageController, :home
  end
end
