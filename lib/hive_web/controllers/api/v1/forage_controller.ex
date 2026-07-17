defmodule HiveWeb.Api.V1.ForageController do
  use HiveWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Hive.Forage
  alias HiveWeb.Api.V1.Presenter
  alias HiveWeb.Api.V1.Schemas.Error
  alias HiveWeb.Api.V1.Schemas.ForageItemResponse
  alias HiveWeb.Api.V1.Schemas.ForageListResponse
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  tags(["Forage"])
  security([%{"oauth2" => ["mobile"]}])

  operation(:index,
    summary: "List visible forage items",
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer, minimum: 1, default: 1}],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100, default: 20}
      ],
      type: [in: :query, type: :string],
      status: [in: :query, type: :string],
      query: [in: :query, type: :string]
    ],
    responses: [
      ok: {"Forage items", "application/json", ForageListResponse},
      unprocessable_entity: OpenApiSpex.JsonErrorResponse.response(),
      unauthorized: {"Invalid access token", "application/json", Error}
    ]
  )

  operation(:show,
    summary: "Get a visible forage item",
    parameters: [
      item_id: [in: :path, type: :string, required: true]
    ],
    responses: [
      ok: {"Forage item", "application/json", ForageItemResponse},
      unauthorized: {"Invalid access token", "application/json", Error},
      not_found: {"Forage item not found", "application/json", Error}
    ]
  )

  def index(conn, params) do
    opts =
      [
        page: param(params, "page", 1),
        page_size: param(params, "page_size", 20),
        type: optional_param(params, "type"),
        status: optional_param(params, "status"),
        query: optional_param(params, "query")
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    {items, meta} = Forage.list_forage_items_for_user(conn.assigns.current_user, opts)

    json(conn, %{
      data: Enum.map(items, &Presenter.forage_item/1),
      pagination: Presenter.pagination(meta)
    })
  end

  def show(conn, params) do
    item_id = param(params, "item_id", nil)

    case Forage.get_item_for_user(item_id, conn.assigns.current_user) do
      {:ok, item} -> json(conn, %{data: Presenter.forage_item(item)})
      {:error, _reason} -> not_found(conn)
    end
  end

  defp param(params, key, default),
    do: Map.get(params, key, Map.get(params, String.to_atom(key), default))

  defp optional_param(params, key),
    do: Map.get(params, key, Map.get(params, String.to_atom(key)))

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found", error_description: "Forage item not found."})
  end
end
