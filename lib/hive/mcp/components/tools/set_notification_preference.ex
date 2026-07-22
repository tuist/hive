defmodule Hive.MCP.Components.Tools.SetNotificationPreference do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "set_notification_preference",
    title: "Set Notification Preference",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "required" => ["topic", "cadence"],
      "properties" => %{
        "topic" => %{
          "type" => "string",
          "enum" => [
            "forage_new_items",
            "forage_item_updates",
            "spec_new",
            "spec_updates",
            "domain_drops",
            "weekly_drop_digest"
          ]
        },
        "scope_id" => %{
          "type" => "string",
          "description" =>
            "Required for domain_drops, forage_item_updates, and spec_updates. Use the resource's internal identifier."
        },
        "cadence" => %{"type" => "string", "enum" => ["off", "daily", "immediate"]}
      },
      "additionalProperties" => false
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "enabled" => %{"type" => "boolean"},
          "topic" => %{"type" => "string"},
          "scope_id" => %{"type" => "string"},
          "cadence" => %{"type" => "string"}
        },
        ["enabled", "topic", "scope_id", "cadence"]
      )

  alias Hive.Domains
  alias Hive.Forage
  alias Hive.Notifications
  alias Hive.Specs

  @topics %{
    "forage_new_items" => :forage_new_items,
    "forage_item_updates" => :forage_item_updates,
    "spec_new" => :spec_new,
    "spec_updates" => :spec_updates,
    "domain_drops" => :domain_drops,
    "weekly_drop_digest" => :weekly_drop_digest
  }
  @global_topics [:forage_new_items, :spec_new, :weekly_drop_digest]
  @cadences %{"daily" => :daily, "immediate" => :immediate}

  @impl EMCP.Tool
  def description do
    "Enable, change, or disable one email subscription for the authenticated Hive user."
  end

  @impl EMCP.Tool
  def call(conn, %{"topic" => topic_value, "cadence" => cadence_value} = args) do
    user = conn.assigns.current_user

    with {:ok, topic} <- fetch(@topics, topic_value),
         {:ok, scope_id} <- scope_id(topic, Map.get(args, "scope_id")),
         :ok <- validate_cadence(topic, cadence_value),
         :ok <- authorize(topic, scope_id, cadence_value, user) do
      set_preference(user, topic, scope_id, cadence_value)
    else
      {:error, reason} -> json_response(%{error: Atom.to_string(reason)})
    end
  end

  defp set_preference(user, topic, scope_id, "off") do
    Notifications.unsubscribe(user, topic, scope_id)
    preference_response(topic, scope_id, "off")
  end

  defp set_preference(user, topic, scope_id, cadence_value) do
    cadence = Map.fetch!(@cadences, cadence_value)

    case Notifications.subscribe(user, topic, scope_id: scope_id, cadence: cadence) do
      {:ok, _subscription} -> preference_response(topic, scope_id, cadence_value)
      {:error, _changeset} -> json_response(%{error: "invalid_preference"})
    end
  end

  defp preference_response(topic, scope_id, "off") do
    json_response(%{
      enabled: false,
      topic: Atom.to_string(topic),
      scope_id: scope_id,
      cadence: "off"
    })
  end

  defp preference_response(topic, scope_id, cadence) do
    json_response(%{
      enabled: true,
      topic: Atom.to_string(topic),
      scope_id: scope_id,
      cadence: cadence
    })
  end

  defp scope_id(topic, _scope_id) when topic in @global_topics, do: {:ok, "global"}
  defp scope_id(_topic, scope_id) when is_binary(scope_id) and scope_id != "", do: {:ok, scope_id}
  defp scope_id(_topic, _scope_id), do: {:error, :scope_id_required}

  defp validate_cadence(:weekly_drop_digest, cadence) when cadence in ["off", "immediate"],
    do: :ok

  defp validate_cadence(_topic, cadence) when cadence in ["off", "daily", "immediate"], do: :ok
  defp validate_cadence(_topic, _cadence), do: {:error, :invalid_cadence}

  defp authorize(_topic, _scope_id, "off", _user), do: :ok
  defp authorize(topic, _scope_id, _cadence, _user) when topic in @global_topics, do: :ok

  defp authorize(:domain_drops, scope_id, _cadence, user) do
    case Domains.fetch_visible_domain(scope_id, user) do
      {:ok, _domain} -> :ok
      _error -> {:error, :not_found}
    end
  end

  defp authorize(:forage_item_updates, scope_id, _cadence, user) do
    case Forage.get_item_for_user(scope_id, user) do
      {:ok, _item} -> :ok
      _error -> {:error, :not_found}
    end
  end

  defp authorize(:spec_updates, scope_id, _cadence, user) do
    try do
      spec = Specs.get_spec!(scope_id)
      if Specs.can_view?(spec, user), do: :ok, else: {:error, :not_found}
    rescue
      Ecto.NoResultsError -> {:error, :not_found}
      Ecto.Query.CastError -> {:error, :not_found}
    end
  end

  defp fetch(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :invalid_topic}
    end
  end
end
