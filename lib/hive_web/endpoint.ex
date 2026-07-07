defmodule HiveWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hive

  @session_options [
    store: :cookie,
    key: "_hive_key",
    signing_salt: "9/MYtbni",
    same_site: "Lax"
  ]

  @live_socket_connect_info [session: @session_options]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: @live_socket_connect_info],
    longpoll: [connect_info: @live_socket_connect_info]

  plug Plug.Static,
    at: "/",
    from: :hive,
    gzip: false,
    only: HiveWeb.static_paths()

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :hive
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug Sentry.PlugContext

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    body_reader: {HiveWeb.CacheBodyReader, :read_body, []},
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug HiveWeb.Router
end
