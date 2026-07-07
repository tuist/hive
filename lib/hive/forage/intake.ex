defmodule Hive.Forage.Intake do
  @moduledoc """
  Shared forage intake entry point for dashboard, Slack, and Model Context
  Protocol callers.
  """

  alias Hive.Accounts.User
  alias Hive.Audit
  alias Hive.Auth
  alias Hive.Domains.GitHubRepository
  alias Hive.Forage
  alias Hive.Forage.FeatureRequest
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.IntakeSettings
  alias Hive.GitHub.Issues
  alias Hive.Repo

  @requester_key {__MODULE__, :requester}
  @settings_id "default"

  defmodule Result do
    @moduledoc false

    defstruct [
      :destination,
      :type,
      :source_record,
      :hive_path,
      :external_url,
      :external_label,
      :target_type,
      :target_id,
      :target_label
    ]
  end

  @doc """
  Returns normalized intake configuration.
  """
  def config(conf \\ []) do
    %{
      destination: normalize_destination(config_value(conf, :destination)) || :hive_item,
      github_repository: normalize_repository(config_value(conf, :github_repository))
    }
  end

  def settings do
    case Repo.get(IntakeSettings, @settings_id) do
      %IntakeSettings{} = settings ->
        preload_settings(settings)

      nil ->
        create_default_settings()
    end
  end

  def change_settings(%IntakeSettings{} = settings, attrs \\ %{}) do
    IntakeSettings.changeset(settings, attrs)
  end

  def update_settings(%IntakeSettings{} = settings, attrs) do
    settings
    |> IntakeSettings.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, settings} -> {:ok, preload_settings(settings)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def available_github_labels(opts \\ []) when is_list(opts) do
    case intake_config(opts) do
      %{destination: :github_issue} ->
        with {:ok, repository} <- resolve_github_repository(opts),
             {:ok, labels} <- Issues.list_labels(repository, Keyword.get(opts, :github, [])) do
          {:ok, normalize_label_options(labels)}
        end

      _config ->
        {:ok, []}
    end
  end

  def with_requester(user, fun) when is_function(fun, 0) do
    previous = Process.get(@requester_key)

    try do
      put_requester(user)
      fun.()
    after
      restore_requester(previous)
    end
  end

  def current_requester, do: Process.get(@requester_key)

  def create(attrs, user, opts \\ [])

  def create(attrs, %User{} = user, opts) when is_map(attrs) and is_list(opts) do
    with {:ok, item} <- validate_attrs(attrs),
         {:ok, destination} <- selected_destination(attrs, opts),
         {:ok, result} <- create_with_destination(destination, item, attrs, user, opts) do
      record_created(result, attrs, user, opts)
      {:ok, result}
    end
  end

  def create(_attrs, _user, _opts), do: {:error, :unauthorized}

  defp create_with_destination(:hive_item, item, _attrs, user, _opts) do
    source = source_for_type(item.type)

    if Forage.can_create?(source, user) do
      item
      |> manual_attrs()
      |> Forage.create_forage_item(user)
      |> case do
        {:ok, feature_request} -> {:ok, hive_item_result(feature_request)}
        {:error, changeset} -> {:error, changeset}
      end
    else
      {:error, :unauthorized}
    end
  end

  defp create_with_destination(:github_issue, item, attrs, user, opts) do
    if Auth.member?(user) do
      with {:ok, repository} <- resolve_github_repository(opts),
           {:ok, labels} <- github_issue_labels(repository, item, attrs, opts),
           {:ok, github_issue} <- create_github_issue(repository, item, attrs, labels, opts),
           {:ok, cached_issue} <- Forage.upsert_repository_github_issue(repository, github_issue) do
        {:ok, github_issue_result(repository, cached_issue)}
      end
    else
      {:error, :unauthorized}
    end
  end

  defp validate_attrs(attrs) do
    %FeatureRequest{}
    |> FeatureRequest.changeset(attrs)
    |> Ecto.Changeset.apply_action(:insert)
  end

  defp selected_destination(attrs, opts) do
    configured_destination =
      opts
      |> intake_config()
      |> Map.fetch!(:destination)

    requested_destination =
      Keyword.get(opts, :destination) || attr(attrs, :destination) || configured_destination

    case normalize_destination(requested_destination) do
      nil -> {:error, :unknown_destination}
      destination -> {:ok, destination}
    end
  end

  defp resolve_github_repository(opts) do
    case opts |> intake_config() |> Map.fetch!(:github_repository) do
      nil ->
        {:error, :github_repository_not_configured}

      %GitHubRepository{} = repository ->
        {:ok, repository}

      %{owner: owner, name: name} ->
        find_github_repository(owner, name)
    end
  end

  defp find_github_repository(owner, name) when is_binary(owner) and is_binary(name) do
    case Repo.get_by(GitHubRepository, owner: owner, name: name) do
      nil -> {:error, :github_repository_not_found}
      repository -> {:ok, repository}
    end
  end

  defp find_github_repository(_owner, _name), do: {:error, :github_repository_not_configured}

  defp create_github_issue(repository, item, attrs, labels, opts) do
    issue_attrs = %{
      title: item.title,
      body: github_issue_body(item, attrs),
      labels: labels
    }

    Issues.create_issue(repository, issue_attrs, Keyword.get(opts, :github, []))
  end

  defp hive_item_result(%FeatureRequest{} = item) do
    %Result{
      destination: :hive_item,
      type: item.type,
      source_record: item,
      hive_path: "/forage/items/manual/#{item.id}",
      target_type: "feature_request",
      target_id: item.id,
      target_label: item.title
    }
  end

  defp github_issue_result(repository, %GitHubIssue{} = issue) do
    %Result{
      destination: :github_issue,
      type: :github_issue,
      source_record: issue,
      hive_path: "/forage/items/github-issue/#{issue.id}",
      external_url: GitHubIssue.html_url(%{issue | github_repository: repository}),
      external_label: "##{issue.number}",
      target_type: "github_issue",
      target_id: issue.id,
      target_label: issue.title
    }
  end

  defp record_created(%Result{} = result, attrs, %User{} = user, opts) do
    Audit.record(
      "forage.intake.created",
      %{
        actor: user,
        target_type: result.target_type,
        target_id: result.target_id,
        target_label: result.target_label,
        metadata:
          %{
            destination: Atom.to_string(result.destination),
            external_url: result.external_url,
            path: result.hive_path,
            source_url: attr(attrs, :source_url),
            type: Atom.to_string(result.type)
          }
          |> reject_empty()
      },
      audit_opts(opts)
    )
  end

  defp audit_opts(opts) do
    opts
    |> Keyword.take([:interface])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp manual_attrs(item) do
    %{
      "type" => Atom.to_string(item.type),
      "title" => item.title,
      "description" => item.description
    }
  end

  defp github_issue_body(item, attrs) do
    source_url = present_string(attr(attrs, :source_url))
    source_label = present_string(attr(attrs, :source_label)) || "Source"

    case source_url do
      nil -> item.description
      url -> "#{item.description}\n\n---\n#{source_label}: #{url}"
    end
  end

  defp github_issue_labels(repository, item, attrs, opts) do
    default_labels = default_github_issue_labels(item)
    requested_labels = requested_github_labels(attrs)

    if requested_labels == [] do
      {:ok, default_labels}
    else
      with {:ok, available_labels} <-
             Issues.list_labels(repository, Keyword.get(opts, :github, [])),
           {:ok, labels} <- validate_requested_github_labels(requested_labels, available_labels) do
        {:ok, Enum.uniq(default_labels ++ labels)}
      end
    end
  end

  defp default_github_issue_labels(%FeatureRequest{type: :feature_request}), do: ["enhancement"]
  defp default_github_issue_labels(%FeatureRequest{type: :bug_report}), do: ["bug"]
  defp default_github_issue_labels(%FeatureRequest{type: :feedback}), do: ["feedback"]

  defp source_for_type(:feature_request), do: Forage.get_source!(:feature_requests)
  defp source_for_type(:bug_report), do: Forage.get_source!(:bug_reports)
  defp source_for_type(:feedback), do: Forage.get_source!(:feedback)

  defp intake_config(opts) do
    case Keyword.fetch(opts, :config) do
      {:ok, conf} -> config(conf)
      :error -> settings() |> config()
    end
  end

  defp normalize_destination(value) when value in [:hive_item, "hive_item"], do: :hive_item

  defp normalize_destination(value) when value in [:github_issue, "github_issue"],
    do: :github_issue

  defp normalize_destination(_value), do: nil

  defp normalize_repository(%IntakeSettings{github_repository: %GitHubRepository{} = repository}) do
    repository
  end

  defp normalize_repository(%IntakeSettings{}), do: nil

  defp normalize_repository(%GitHubRepository{} = repository), do: repository

  defp normalize_repository(%{owner: owner, name: name}) do
    %{owner: normalize_repository_part(owner), name: normalize_repository_part(name)}
  end

  defp normalize_repository(value) when is_binary(value) do
    case String.split(String.trim(value), "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        %{owner: normalize_repository_part(owner), name: normalize_repository_part(name)}

      _other ->
        nil
    end
  end

  defp normalize_repository(_value), do: nil

  defp normalize_repository_part(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_repository_part(value), do: value

  defp config_value(%IntakeSettings{} = settings, :destination), do: settings.destination
  defp config_value(%IntakeSettings{} = settings, :github_repository), do: settings

  defp config_value(conf, key) when is_map(conf) do
    Map.get(conf, key) || Map.get(conf, Atom.to_string(key))
  end

  defp config_value(conf, key) when is_list(conf), do: Keyword.get(conf, key)
  defp config_value(_conf, _key), do: nil

  defp attr(attrs, key) when is_map(attrs) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_value), do: nil

  defp requested_github_labels(attrs) do
    []
    |> append_requested_labels(attr(attrs, :github_label))
    |> append_requested_labels(attr(attrs, :github_labels))
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&normalize_label_name/1)
    |> Enum.take(3)
  end

  defp append_requested_labels(labels, values) when is_list(values), do: labels ++ values
  defp append_requested_labels(labels, value) when is_binary(value), do: labels ++ [value]
  defp append_requested_labels(labels, _value), do: labels

  defp validate_requested_github_labels(requested_labels, available_labels) do
    available_by_name =
      available_labels
      |> normalize_label_options()
      |> Map.new(fn %{name: name} -> {normalize_label_name(name), name} end)

    unknown_labels =
      Enum.reject(requested_labels, fn label ->
        Map.has_key?(available_by_name, normalize_label_name(label))
      end)

    if unknown_labels == [] do
      {:ok,
       Enum.map(requested_labels, fn label ->
         Map.fetch!(available_by_name, normalize_label_name(label))
       end)}
    else
      {:error, {:unknown_github_labels, unknown_labels}}
    end
  end

  defp normalize_label_options(labels) when is_list(labels) do
    labels
    |> Enum.map(&normalize_label_option/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_label_options(_labels), do: []

  defp normalize_label_option(%{name: name} = label) when is_binary(name) do
    %{
      name: name,
      description: Map.get(label, :description),
      color: Map.get(label, :color)
    }
  end

  defp normalize_label_option(%{"name" => name} = label) when is_binary(name) do
    %{
      name: name,
      description: Map.get(label, "description"),
      color: Map.get(label, "color")
    }
  end

  defp normalize_label_option(_label), do: nil

  defp normalize_label_name(label) when is_binary(label) do
    label
    |> String.trim()
    |> String.downcase()
  end

  defp reject_empty(map) do
    Map.reject(map, fn {_key, value} -> value in [nil, ""] end)
  end

  defp put_requester(%User{} = user), do: Process.put(@requester_key, user)
  defp put_requester(_user), do: Process.delete(@requester_key)

  defp restore_requester(nil), do: Process.delete(@requester_key)
  defp restore_requester(previous), do: Process.put(@requester_key, previous)

  defp create_default_settings do
    %IntakeSettings{id: @settings_id}
    |> IntakeSettings.changeset(%{})
    |> Repo.insert(on_conflict: :nothing)

    IntakeSettings
    |> Repo.get!(@settings_id)
    |> preload_settings()
  end

  defp preload_settings(%IntakeSettings{} = settings) do
    Repo.preload(settings, :github_repository, force: true)
  end
end
