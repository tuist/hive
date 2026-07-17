defmodule HiveWeb.Api.V1.DropController do
  use HiveWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Hive.Drops
  alias Hive.Drops.Drop
  alias HiveWeb.Api.V1.Presenter
  alias HiveWeb.Api.V1.Schemas.DropListResponse
  alias HiveWeb.Api.V1.Schemas.DropResponse
  alias HiveWeb.Api.V1.Schemas.Error
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  tags(["Drops"])
  security([%{"oauth2" => ["mobile"]}])

  operation(:index,
    summary: "List visible drops",
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer, minimum: 1, default: 1}],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100, default: 20}
      ],
      source_type: [
        in: :query,
        schema: %Schema{type: :string, enum: ["github_release", "rss"]}
      ],
      query: [in: :query, type: :string]
    ],
    responses: [
      ok: {"Drops", "application/json", DropListResponse},
      unprocessable_entity: OpenApiSpex.JsonErrorResponse.response(),
      unauthorized: {"Invalid access token", "application/json", Error}
    ]
  )

  operation(:show,
    summary: "Get a visible drop",
    parameters: [
      number: [in: :path, required: true, schema: %Schema{type: :integer, minimum: 1}]
    ],
    responses: [
      ok: {"Drop", "application/json", DropResponse},
      unauthorized: {"Invalid access token", "application/json", Error},
      not_found: {"Drop not found", "application/json", Error}
    ]
  )

  def index(conn, params) do
    opts = [
      user: conn.assigns.current_user,
      page: param(params, "page", 1),
      page_size: param(params, "page_size", 20),
      source_type: source_type(optional_param(params, "source_type")),
      query: optional_param(params, "query")
    ]

    {drops, meta} = Drops.list_drops(opts)

    json(conn, %{
      data: Enum.map(drops, &Presenter.drop/1),
      pagination: Presenter.pagination(meta)
    })
  end

  def show(conn, params) do
    case Drops.fetch_visible_drop(param(params, "number", nil), conn.assigns.current_user) do
      {:ok, drop} -> json(conn, %{data: Presenter.drop(drop)})
      {:error, :not_found} -> not_found(conn)
    end
  end

  defp param(params, key, default),
    do: Map.get(params, key, Map.get(params, String.to_atom(key), default))

  defp optional_param(params, key),
    do: Map.get(params, key, Map.get(params, String.to_atom(key)))

  defp source_type(nil), do: nil

  defp source_type(value),
    do: Enum.find(Drop.source_types(), &(to_string(&1) == value))

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found", error_description: "Drop not found."})
  end
end
