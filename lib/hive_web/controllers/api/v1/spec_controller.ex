defmodule HiveWeb.Api.V1.SpecController do
  use HiveWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Hive.Specs
  alias HiveWeb.Api.V1.Presenter
  alias HiveWeb.Api.V1.Schemas.Error
  alias HiveWeb.Api.V1.Schemas.SpecListResponse
  alias HiveWeb.Api.V1.Schemas.SpecResponse
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  tags(["Specs"])
  security([%{"oauth2" => ["mobile"]}])

  operation(:index,
    summary: "List visible specs",
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer, minimum: 1, default: 1}],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100, default: 20}
      ],
      status: [in: :query, type: :string],
      query: [in: :query, type: :string]
    ],
    responses: [
      ok: {"Specs", "application/json", SpecListResponse},
      unprocessable_entity: OpenApiSpex.JsonErrorResponse.response(),
      unauthorized: {"Invalid access token", "application/json", Error}
    ]
  )

  operation(:show,
    summary: "Get a visible spec",
    parameters: [
      number: [in: :path, required: true, schema: %Schema{type: :integer, minimum: 1}]
    ],
    responses: [
      ok: {"Spec", "application/json", SpecResponse},
      unauthorized: {"Invalid access token", "application/json", Error},
      not_found: {"Spec not found", "application/json", Error}
    ]
  )

  def index(conn, params) do
    page = param(params, "page", 1)
    page_size = param(params, "page_size", 20)

    specs =
      [user: conn.assigns.current_user, status: spec_status(optional_param(params, "status"))]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Specs.list_specs()
      |> filter_specs(optional_param(params, "query"))

    {visible_specs, meta} = paginate(specs, page, page_size)

    json(conn, %{
      data: Enum.map(visible_specs, &Presenter.spec/1),
      pagination: Presenter.pagination(meta)
    })
  end

  def show(conn, params) do
    number = param(params, "number", nil)
    spec = Specs.get_spec_by_number!(number)

    if Specs.can_view?(spec, conn.assigns.current_user) do
      json(conn, %{data: Presenter.spec(spec)})
    else
      not_found(conn)
    end
  rescue
    Ecto.NoResultsError -> not_found(conn)
  end

  defp filter_specs(specs, nil), do: specs

  defp filter_specs(specs, query) do
    query = String.downcase(query)

    Enum.filter(specs, fn spec ->
      Enum.any?([spec.title, spec.summary, spec.body], fn value ->
        is_binary(value) and String.contains?(String.downcase(value), query)
      end)
    end)
  end

  defp paginate(specs, page, page_size) do
    total_count = length(specs)
    total_pages = if total_count == 0, do: 0, else: ceil(total_count / page_size)

    items = Enum.slice(specs, (page - 1) * page_size, page_size)

    {items,
     %{page: page, page_size: page_size, total_count: total_count, total_pages: total_pages}}
  end

  defp param(params, key, default),
    do: Map.get(params, key, Map.get(params, String.to_atom(key), default))

  defp optional_param(params, key),
    do: Map.get(params, key, Map.get(params, String.to_atom(key)))

  defp spec_status(nil), do: nil

  defp spec_status(value) do
    Enum.find(Hive.Specs.Spec.statuses(), &(to_string(&1) == value))
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found", error_description: "Spec not found."})
  end
end
