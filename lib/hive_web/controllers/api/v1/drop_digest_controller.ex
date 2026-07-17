defmodule HiveWeb.Api.V1.DropDigestController do
  use HiveWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Hive.Drops.WeeklyDigests
  alias HiveWeb.Api.V1.Presenter
  alias HiveWeb.Api.V1.Schemas.DropDigestListResponse
  alias HiveWeb.Api.V1.Schemas.DropDigestResponse
  alias HiveWeb.Api.V1.Schemas.Error
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  tags(["Drops"])
  security([%{"oauth2" => ["mobile"]}])

  operation(:index,
    summary: "List published Drops weekly digests",
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer, minimum: 1, default: 1}],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100, default: 20}
      ],
      query: [in: :query, type: :string]
    ],
    responses: [
      ok: {"Drops weekly digests", "application/json", DropDigestListResponse},
      unprocessable_entity: OpenApiSpex.JsonErrorResponse.response(),
      unauthorized: {"Invalid access token", "application/json", Error}
    ]
  )

  operation(:show,
    summary: "Get a published Drops weekly digest",
    parameters: [
      week_start: [in: :path, required: true, schema: %Schema{type: :string, format: :date}]
    ],
    responses: [
      ok: {"Drops weekly digest", "application/json", DropDigestResponse},
      unauthorized: {"Invalid access token", "application/json", Error},
      not_found: {"Drops weekly digest not found", "application/json", Error}
    ]
  )

  def index(conn, params) do
    {digests, meta} =
      WeeklyDigests.list_published_page(
        page: param(params, "page", 1),
        page_size: param(params, "page_size", 20),
        query: optional_param(params, "query")
      )

    json(conn, %{
      data: Enum.map(digests, &Presenter.drop_digest/1),
      pagination: Presenter.pagination(meta)
    })
  end

  def show(conn, params) do
    reference =
      case param(params, "week_start", nil) do
        %Date{} = date -> Date.to_iso8601(date)
        value -> value
      end

    case WeeklyDigests.fetch_published(reference) do
      {:ok, digest} -> json(conn, %{data: Presenter.drop_digest(digest)})
      {:error, :not_found} -> not_found(conn)
    end
  end

  defp param(params, key, default),
    do: Map.get(params, key, Map.get(params, String.to_atom(key), default))

  defp optional_param(params, key),
    do: Map.get(params, key, Map.get(params, String.to_atom(key)))

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found", error_description: "Drops weekly digest not found."})
  end
end
