defmodule HiveWeb.Api.V1.ErrorsController do
  use HiveWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Hive.Errors
  alias Hive.Errors.Issue
  alias Hive.Errors.Policy
  alias HiveWeb.Api.V1.Presenter
  alias HiveWeb.Api.V1.Schemas.Error
  alias HiveWeb.Api.V1.Schemas.ErrorIssueListResponse
  alias HiveWeb.Api.V1.Schemas.ErrorIssueResponse
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  tags(["Errors"])
  security([%{"oauth2" => ["mobile.errors.read"]}])

  operation(:index,
    summary: "List error issues visible to the current user",
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer, minimum: 1, default: 1}],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100, default: 20}
      ],
      status: [
        in: :query,
        schema: %Schema{type: :string, enum: ["unresolved", "resolved", "ignored"]}
      ],
      query: [in: :query, type: :string]
    ],
    responses: [
      ok: {"Error issues", "application/json", ErrorIssueListResponse},
      unprocessable_entity: OpenApiSpex.JsonErrorResponse.response(),
      unauthorized: {"Invalid access token", "application/json", Error},
      forbidden: {"Insufficient role", "application/json", Error}
    ]
  )

  operation(:show,
    summary: "Get a single error issue",
    parameters: [
      id: [in: :path, type: :string, required: true]
    ],
    responses: [
      ok: {"Error issue", "application/json", ErrorIssueResponse},
      unauthorized: {"Invalid access token", "application/json", Error},
      forbidden: {"Insufficient role", "application/json", Error},
      not_found: {"Error issue not found", "application/json", Error}
    ]
  )

  def index(conn, params) do
    if authorized?(conn) do
      opts =
        [
          page: param(params, "page", 1),
          page_size: param(params, "page_size", 20),
          status: status(optional_param(params, "status")),
          search: optional_param(params, "query")
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      {issues, meta} = Errors.paginate_issues(opts)
      origin = HiveWeb.RequestOrigin.from_conn(conn)

      json(conn, %{
        data:
          Enum.map(issues, fn issue ->
            Presenter.error_issue(issue,
              latest_event: latest_event(issue.id),
              dashboard_url: dashboard_url(origin, issue.id)
            )
          end),
        pagination: Presenter.pagination(meta)
      })
    else
      forbidden(conn)
    end
  end

  def show(conn, params) do
    cond do
      not authorized?(conn) ->
        forbidden(conn)

      true ->
        case Errors.fetch_issue(param(params, "id", nil)) do
          {:ok, issue} ->
            origin = HiveWeb.RequestOrigin.from_conn(conn)

            json(conn, %{
              data:
                Presenter.error_issue(issue,
                  latest_event: latest_event(issue.id),
                  dashboard_url: dashboard_url(origin, issue.id)
                )
            })

          {:error, :not_found} ->
            not_found(conn)
        end
    end
  end

  defp latest_event(issue_id) do
    case Errors.list_events_for_issue(issue_id, limit: 1) do
      [event | _] -> event
      _ -> nil
    end
  end

  defp dashboard_url(origin, issue_id),
    do: origin <> "/errors/" <> issue_id

  defp authorized?(conn),
    do: Policy.authorize?(:error_issue_read, conn.assigns.current_user, nil)

  defp forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: "forbidden",
      error_description: "Your role cannot read error issues."
    })
  end

  defp status(nil), do: nil

  defp status(value) do
    Enum.find(Issue.statuses(), &(to_string(&1) == value))
  end

  defp param(params, key, default),
    do: Map.get(params, key, Map.get(params, String.to_atom(key), default))

  defp optional_param(params, key),
    do: Map.get(params, key, Map.get(params, String.to_atom(key)))

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "not_found", error_description: "Error issue not found."})
  end
end
