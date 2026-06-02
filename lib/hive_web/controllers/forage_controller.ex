defmodule HiveWeb.ForageController do
  use HiveWeb, :controller

  alias Hive.Forage
  alias HiveWeb.ForageHTML

  def feature_requests(conn, _params) do
    render_forage(conn, ForageHTML.feature_requests_page(conn))
  end

  def new_feature_request(conn, _params) do
    with_create_permission(conn, :feature_requests, fn conn, _user ->
      render_forage(
        conn,
        ForageHTML.new_feature_request_page(conn, Forage.change_feature_request())
      )
    end)
  end

  def create_feature_request(conn, %{"feature_request" => feature_request_params}) do
    with_create_permission(conn, :feature_requests, fn conn, user ->
      case Forage.create_feature_request(feature_request_params, user) do
        {:ok, _feature_request} ->
          conn
          |> put_flash(:info, "Feature request submitted.")
          |> redirect(to: ~p"/forage/feature-requests")

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render_forage(ForageHTML.new_feature_request_page(conn, changeset))
      end
    end)
  end

  def bug_reports(conn, _params) do
    render_forage(conn, ForageHTML.placeholder_page(conn, :bug_reports))
  end

  def feedback(conn, _params) do
    render_forage(conn, ForageHTML.placeholder_page(conn, :feedback))
  end

  def grafana_alerts(conn, _params) do
    if Forage.can_access?(Forage.get_source!(:grafana_alerts), current_user(conn)) do
      render_forage(conn, ForageHTML.placeholder_page(conn, :grafana_alerts))
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(:not_found, "Not Found")
    end
  end

  defp render_forage(conn, content) do
    html(conn, Phoenix.HTML.Safe.to_iodata(content))
  end

  defp with_create_permission(conn, source_id, fun) do
    source = Forage.get_source!(source_id)
    user = current_user(conn)

    if Forage.can_create?(source, user) do
      fun.(conn, user)
    else
      conn
      |> put_flash(:error, "Log in to submit feature requests.")
      |> redirect(to: ~p"/login")
    end
  end

  defp current_user(conn), do: Hive.Auth.current_user(conn)
end
