defmodule HiveWeb.Api.V1.SessionController do
  use HiveWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias HiveWeb.Api.V1.Presenter
  alias HiveWeb.Api.V1.Schemas.Error
  alias HiveWeb.Api.V1.Schemas.UserResponse

  tags(["Session"])
  security([%{"oauth2" => ["mobile"]}])

  operation(:show,
    summary: "Get the current user",
    responses: [
      ok: {"Current user", "application/json", UserResponse},
      unauthorized: {"Invalid access token", "application/json", Error}
    ]
  )

  def show(conn, _params) do
    json(conn, %{data: Presenter.user(conn.assigns.current_user)})
  end
end
