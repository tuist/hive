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

    get "/", PageController, :home
  end
end
