defmodule Hive.Flights do
  @moduledoc """
  Durable agent executions that can be inspected and continued after their
  original sandbox has stopped.
  """

  import Ecto.Query

  alias Hive.Flights.Flight
  alias Hive.Flights.Policy
  alias Hive.Forage
  alias Hive.Repo

  @default_page_size 20
  @max_page_size 100

  def statuses, do: Flight.statuses()
  def objectives, do: Flight.objectives()
  def objective_outcomes, do: Flight.objective_outcomes()

  def start_for_item(item, repository_id, user, opts \\ []) do
    Hive.Forage.CodingRuns.create_for_item(item, repository_id, user, opts)
  end

  def start_for_grafana_alert(alert, repository_id, user, opts \\ []) do
    with {:ok, item} <- Hive.Forage.get_item_for_user("grafana_alert:#{alert.id}", user) do
      start_for_item(item, repository_id, user, opts)
    end
  end

  def list_flights_for_user(user, opts \\ []) do
    if Policy.authorize?(:flight_read, user, nil) do
      {flights, meta} = list_flights(opts)
      {Enum.map(flights, &attach_forage_item(&1, user)), meta}
    else
      {[], pagination_meta(0, 1, normalize_page_size(opts[:page_size]))}
    end
  end

  def get_flight(id) when is_binary(id) do
    Flight
    |> preload([:repository, :requested_by])
    |> Repo.get(id)
  rescue
    Ecto.Query.CastError -> nil
  end

  def get_flight_for_user(id, user) when is_binary(id) do
    if Policy.authorize?(:flight_read, user, nil) do
      case get_flight(id) do
        nil -> nil
        flight -> attach_forage_item(flight, user)
      end
    end
  end

  def filter_options(user) do
    if Policy.authorize?(:flight_read, user, nil) do
      %{
        statuses: statuses(),
        objectives: objectives(),
        objective_outcomes: objective_outcomes(),
        runners: distinct_values(:runner),
        repositories: distinct_values(:repository_full_name)
      }
    else
      %{
        statuses: statuses(),
        objectives: objectives(),
        objective_outcomes: objective_outcomes(),
        runners: [],
        repositories: []
      }
    end
  end

  def serialize(%Flight{} = flight, opts \\ []) do
    include_session? = Keyword.get(opts, :include_session?, true)

    %{
      id: flight.id,
      status: Atom.to_string(flight.status),
      objective: Atom.to_string(flight.objective),
      objective_outcome: atom_string(flight.objective_outcome),
      runner: flight.runner,
      runner_id: flight.runner_id,
      repository: flight.repository_full_name,
      forage_item: serialize_forage_item(flight.forage_item),
      input: flight.input || %{},
      trigger: flight.trigger || %{},
      session: if(include_session?, do: flight.session, else: nil),
      result: flight.result,
      error: flight.error,
      requested_by: serialize_requester(flight.requested_by),
      parent_flight_id: flight.parent_flight_id,
      started_at: iso8601(flight.started_at),
      completed_at: iso8601(flight.completed_at),
      inserted_at: iso8601(flight.inserted_at),
      updated_at: iso8601(flight.updated_at),
      path: path(flight)
    }
  end

  def path(%Flight{id: id}), do: "/flights/#{id}"
  def path(id) when is_binary(id), do: "/flights/#{id}"

  def forage_item_path(%{id: "manual:" <> id}), do: "/forage/items/manual/#{id}"
  def forage_item_path(%{id: "github_issue:" <> id}), do: "/forage/items/github-issue/#{id}"
  def forage_item_path(%{id: "grafana_alert:" <> id}), do: "/forage/items/grafana-alert/#{id}"
  def forage_item_path(_item), do: nil

  def status_label(:queued), do: "Queued"
  def status_label(:running), do: "Running"
  def status_label(:succeeded), do: "Succeeded"
  def status_label(:failed), do: "Failed"

  def status_color(:queued), do: "neutral"
  def status_color(:running), do: "information"
  def status_color(:succeeded), do: "success"
  def status_color(:failed), do: "destructive"

  def objective_label(:investigate), do: "Investigate"
  def objective_label(:reproduce), do: "Reproduce"
  def objective_label(:fix), do: "Fix"

  def objective_outcome_label(:investigated), do: "Investigated"
  def objective_outcome_label(:reproduced), do: "Reproduced"
  def objective_outcome_label(:not_reproduced), do: "Not reproduced"
  def objective_outcome_label(:fixed), do: "Fixed"
  def objective_outcome_label(:no_change), do: "No change"
  def objective_outcome_label(:inconclusive), do: "Inconclusive"
  def objective_outcome_label(nil), do: nil

  def objective_outcome_color(:reproduced), do: "attention"
  def objective_outcome_color(:not_reproduced), do: "neutral"
  def objective_outcome_color(:fixed), do: "success"
  def objective_outcome_color(:investigated), do: "information"
  def objective_outcome_color(:no_change), do: "neutral"
  def objective_outcome_color(:inconclusive), do: "attention"
  def objective_outcome_color(nil), do: "neutral"

  defp list_flights(opts) do
    page = normalize_page(opts[:page])
    page_size = normalize_page_size(opts[:page_size])

    filtered_query =
      Flight
      |> maybe_filter_status(opts[:status])
      |> maybe_filter_enum(:objective, opts[:objective], objectives())
      |> maybe_filter_enum(
        :objective_outcome,
        opts[:objective_outcome],
        objective_outcomes()
      )
      |> maybe_filter_exact(:runner, present_string(opts[:runner]))
      |> maybe_filter_exact(:repository_full_name, present_string(opts[:repository]))
      |> maybe_search(present_string(opts[:query]))

    total_count = Repo.aggregate(filtered_query, :count)

    query =
      filtered_query
      |> order_by([flight], desc: flight.inserted_at, desc: flight.id)
      |> select([flight], struct(flight, ^list_fields()))
      |> preload([:repository, :requested_by])

    case page_size do
      :all ->
        {Repo.all(query), pagination_meta(total_count, 1, :all)}

      page_size ->
        total_pages = max(1, ceil(total_count / page_size))
        current_page = min(page, total_pages)

        flights =
          query
          |> limit(^page_size)
          |> offset(^((current_page - 1) * page_size))
          |> Repo.all()

        {flights, pagination_meta(total_count, current_page, page_size)}
    end
  end

  defp attach_forage_item(flight, user) do
    case Forage.get_item_for_user(flight.forage_item_id, user) do
      {:ok, item} -> %{flight | forage_item: item}
      {:error, _reason} -> flight
    end
  end

  defp distinct_values(field) do
    Flight
    |> where([flight], not is_nil(field(flight, ^field)))
    |> select([flight], field(flight, ^field))
    |> distinct(true)
    |> order_by([flight], asc: field(flight, ^field))
    |> Repo.all()
  end

  defp list_fields, do: Flight.__schema__(:fields) -- [:session]

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) when is_binary(status) do
    case Enum.find(statuses(), &(Atom.to_string(&1) == status)) do
      nil -> query
      status -> where(query, [flight], flight.status == ^status)
    end
  end

  defp maybe_filter_status(query, status) when status in [:queued, :running, :succeeded, :failed],
    do: where(query, [flight], flight.status == ^status)

  defp maybe_filter_status(query, _status), do: query

  defp maybe_filter_enum(query, _field, nil, _allowed), do: query

  defp maybe_filter_enum(query, field, value, allowed) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> query
      enum -> where(query, [flight], field(flight, ^field) == ^enum)
    end
  end

  defp maybe_filter_enum(query, field, value, allowed) when is_atom(value) do
    if value in allowed,
      do: where(query, [flight], field(flight, ^field) == ^value),
      else: query
  end

  defp maybe_filter_enum(query, _field, _value, _allowed), do: query

  defp maybe_filter_exact(query, _field, nil), do: query

  defp maybe_filter_exact(query, field, value),
    do: where(query, [flight], field(flight, ^field) == ^value)

  defp maybe_search(query, nil), do: query

  defp maybe_search(query, search) do
    pattern = "%#{escape_like(search)}%"

    where(
      query,
      [flight],
      ilike(flight.repository_full_name, ^pattern) or
        ilike(fragment("COALESCE(?, '')", flight.objective), ^pattern) or
        ilike(fragment("COALESCE(?, '')", flight.objective_outcome), ^pattern) or
        ilike(fragment("COALESCE(?->>'title', '')", flight.input), ^pattern) or
        ilike(fragment("COALESCE(?->>'summary', '')", flight.result), ^pattern) or
        ilike(fragment("COALESCE(?, '')", flight.error), ^pattern)
    )
  end

  defp escape_like(value),
    do:
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

  defp serialize_forage_item(nil), do: nil

  defp serialize_forage_item(item) do
    %{
      id: item.id,
      type: Atom.to_string(item.type),
      title: item.title,
      status: Atom.to_string(item.status),
      path: forage_item_path(item)
    }
  end

  defp serialize_requester(%{id: id, email: email, name: name}),
    do: %{id: id, email: email, name: name}

  defp serialize_requester(_requester), do: nil

  defp normalize_page(page) when is_integer(page) and page > 0, do: page

  defp normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {value, ""} when value > 0 -> value
      _other -> 1
    end
  end

  defp normalize_page(_page), do: 1

  defp normalize_page_size(size) when is_integer(size) and size > 0,
    do: min(size, @max_page_size)

  defp normalize_page_size(:all), do: :all
  defp normalize_page_size(_size), do: @default_page_size

  defp pagination_meta(total_count, _current_page, :all) do
    %{
      current_page: 1,
      page_size: :all,
      total_count: total_count,
      total_pages: 1,
      has_next_page?: false,
      has_previous_page?: false
    }
  end

  defp pagination_meta(total_count, current_page, page_size) do
    total_pages = max(1, ceil(total_count / page_size))

    %{
      current_page: current_page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages,
      has_next_page?: current_page < total_pages,
      has_previous_page?: current_page > 1
    }
  end

  defp present_string(nil), do: nil

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp present_string(_value), do: nil

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp iso8601(%NaiveDateTime{} = value),
    do: value |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

  defp atom_string(nil), do: nil
  defp atom_string(value) when is_atom(value), do: Atom.to_string(value)
end
