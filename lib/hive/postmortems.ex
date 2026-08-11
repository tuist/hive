defmodule Hive.Postmortems do
  @moduledoc """
  Public incident postmortems published by organization members.
  """

  import Ecto.Query

  alias Hive.Accounts.User
  alias Hive.Auth
  alias Ecto.Changeset
  alias Hive.Domains.Domain
  alias Hive.Postmortems.ActionItem
  alias Hive.Postmortems.Embedding
  alias Hive.Postmortems.EmbeddingWorker
  alias Hive.Postmortems.Postmortem
  alias Hive.Repo
  alias HiveWeb.Markdown

  @number_lock_namespace 0x48695645
  @number_lock_key 0x504D4F52

  def can_publish?(user), do: Auth.member?(user)
  def can_edit?(%Postmortem{}, user), do: Auth.member?(user)
  def can_view?(%Postmortem{visibility: :public}, _user), do: true
  def can_view?(%Postmortem{}, user), do: Auth.member?(user)

  def list_postmortems(user \\ nil) do
    Postmortem
    |> apply_visibility(user)
    |> order_by([postmortem], desc: postmortem.inserted_at)
    |> preload([:created_by_user, :domains, action_items: ^action_items_query()])
    |> Repo.all()
  end

  def list_postmortems_page(opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 20)

    query =
      Postmortem
      |> maybe_search(Keyword.get(opts, :query))
      |> maybe_filter_published(Keyword.get(opts, :published))
      |> apply_visibility(Keyword.get(opts, :user))

    total_entries = Repo.aggregate(query, :count)
    total_pages = max(ceil(total_entries / page_size), 1)
    page = min(page, total_pages)

    postmortems =
      query
      |> order_by([postmortem], desc: postmortem.inserted_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload([:created_by_user, :domains, action_items: ^action_items_query()])
      |> Repo.all()

    {postmortems, %{current_page: page, total_pages: total_pages, total_entries: total_entries}}
  end

  def get_postmortem!(id), do: Repo.get!(Postmortem, id)
  def get_postmortem(id), do: Repo.get(Postmortem, id)

  def get_postmortem_by_number!(number),
    do:
      Postmortem
      |> preload([:created_by_user, :domains, action_items: ^action_items_query()])
      |> Repo.get_by!(number: number)

  def get_postmortem_by_number(number),
    do:
      Postmortem
      |> preload([:created_by_user, :domains, action_items: ^action_items_query()])
      |> Repo.get_by(number: number)

  def fetch_visible_postmortem_by_number(number, user) do
    case get_postmortem_by_number(number) do
      %Postmortem{} = postmortem ->
        if(can_view?(postmortem, user), do: {:ok, postmortem}, else: {:error, :not_found})

      _ ->
        {:error, :not_found}
    end
  end

  def change_postmortem(postmortem \\ %Postmortem{}, attrs \\ %{}),
    do: Postmortem.changeset(postmortem, attrs)

  def change_action_item(action_item \\ %ActionItem{}, attrs \\ %{}),
    do: ActionItem.changeset(action_item, attrs)

  def publish_postmortem(attrs, %User{} = user) do
    if can_publish?(user) do
      with {:ok, postmortem} <-
             Repo.transaction(fn ->
               Repo.query!("SELECT pg_advisory_xact_lock($1::integer, $2::integer)", [
                 @number_lock_namespace,
                 @number_lock_key
               ])

               case %Postmortem{}
                    |> Postmortem.changeset(attrs)
                    |> Ecto.Changeset.put_change(:created_by_user_id, user.id)
                    |> Repo.insert() do
                 {:ok, postmortem} ->
                   case put_domains(postmortem, attrs) do
                     {:ok, postmortem} -> postmortem
                     {:error, changeset} -> Repo.rollback(changeset)
                   end

                 {:error, changeset} ->
                   Repo.rollback(changeset)
               end
             end) do
        schedule_indexing(postmortem)
        {:ok, postmortem}
      end
    else
      {:error, :unauthorized}
    end
  end

  def publish_postmortem(_attrs, _user), do: {:error, :unauthorized}

  def update_postmortem(%Postmortem{} = postmortem, attrs, %User{} = user) do
    if can_edit?(postmortem, user) do
      with {:ok, updated_postmortem} <- Repo.update(Postmortem.changeset(postmortem, attrs)),
           {:ok, updated_postmortem} <- put_domains(updated_postmortem, attrs) do
        schedule_indexing(updated_postmortem)
        {:ok, updated_postmortem}
      end
    else
      {:error, :unauthorized}
    end
  end

  def update_postmortem(_postmortem, _attrs, _user), do: {:error, :unauthorized}

  def create_action_item(%Postmortem{} = postmortem, attrs, %User{} = user) do
    if can_edit?(postmortem, user) do
      %ActionItem{postmortem_id: postmortem.id}
      |> ActionItem.changeset(attrs)
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end

  def update_action_item(
        %Postmortem{} = postmortem,
        %ActionItem{} = action_item,
        attrs,
        %User{} = user
      ) do
    if action_item.postmortem_id == postmortem.id and can_edit?(postmortem, user) do
      action_item |> ActionItem.changeset(attrs) |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  def delete_action_item(%Postmortem{} = postmortem, %ActionItem{} = action_item, %User{} = user) do
    if action_item.postmortem_id == postmortem.id and can_edit?(postmortem, user) do
      Repo.delete(action_item)
    else
      {:error, :unauthorized}
    end
  end

  def toggle_action_item(%Postmortem{} = postmortem, %ActionItem{} = action_item, %User{} = user) do
    if action_item.postmortem_id == postmortem.id and can_edit?(postmortem, user) do
      completed_at =
        if action_item.completed_at,
          do: nil,
          else: DateTime.utc_now() |> DateTime.truncate(:second)

      action_item |> Changeset.change(completed_at: completed_at) |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  def index_postmortem(postmortem_id, content_hash, opts \\ []) do
    embed = Keyword.get(opts, :embed, &embed/1)

    case Repo.get(Postmortem, postmortem_id) do
      nil ->
        {:error, :not_found}

      postmortem ->
        if content_hash == content_hash(postmortem.body) do
          case Repo.get_by(Embedding, postmortem_id: postmortem.id) do
            %Embedding{status: :indexed, content_hash: ^content_hash} = embedding ->
              {:ok, embedding}

            _embedding ->
              with {:ok, vector} <- embed.(postmortem.body),
                   {:ok, embedding} <- save_embedding(postmortem.id, content_hash, vector) do
                {:ok, embedding}
              end
          end
        else
          {:ok, :stale}
        end
    end
  end

  def mark_embedding_failed(postmortem_id, content_hash, reason) do
    case Repo.get_by(Embedding, postmortem_id: postmortem_id, content_hash: content_hash) do
      nil ->
        :ok

      embedding ->
        embedding
        |> Embedding.changeset(%{status: :failed, failure_reason: to_string(reason)})
        |> Repo.update()

        :ok
    end
  end

  def semantic_search(query, opts \\ []) when is_binary(query) do
    embed = Keyword.get(opts, :embed, &embed/1)
    limit = Keyword.get(opts, :limit, 10)

    with {:ok, query_embedding} <- embed.(query) do
      results =
        Embedding
        |> where([embedding], embedding.status == :indexed)
        |> preload(:postmortem)
        |> Repo.all()
        |> Enum.map(fn embedding ->
          %{
            postmortem: embedding.postmortem,
            score: ReqLLM.cosine_similarity(query_embedding, embedding.embedding)
          }
        end)
        |> Enum.sort_by(& &1.score, :desc)
        |> Enum.take(limit)

      {:ok, results}
    end
  end

  def title(%Postmortem{body: body}), do: title(body)

  def title(body) when is_binary(body) do
    body
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^\s*#\s+(.+)\s*$/, line) do
        [_, title] -> Markdown.preview(title, 100)
        _no_heading -> nil
      end
    end)
    |> case do
      "" -> "Postmortem"
      nil -> "Postmortem"
      title -> title
    end
  end

  defp maybe_search(query, value) when is_binary(value) and value != "" do
    where(query, [postmortem], ilike(postmortem.body, ^"%#{value}%"))
  end

  defp maybe_search(query, _value), do: query

  defp maybe_filter_published(query, :last_30_days) do
    where(
      query,
      [postmortem],
      postmortem.inserted_at >= ^DateTime.add(DateTime.utc_now(), -30, :day)
    )
  end

  defp maybe_filter_published(query, _value), do: query

  defp apply_visibility(query, user) do
    if Auth.member?(user),
      do: query,
      else: where(query, [postmortem], postmortem.visibility == :public)
  end

  defp action_items_query do
    from action_item in ActionItem,
      order_by: [asc_nulls_first: action_item.completed_at, asc: action_item.inserted_at]
  end

  defp schedule_indexing(postmortem) do
    content_hash = content_hash(postmortem.body)

    %Embedding{}
    |> Embedding.changeset(%{
      postmortem_id: postmortem.id,
      content_hash: content_hash,
      status: :pending,
      embedding: nil,
      failure_reason: nil,
      indexed_at: nil
    })
    |> Repo.insert(
      on_conflict: [
        set: [
          content_hash: content_hash,
          status: :pending,
          embedding: nil,
          failure_reason: nil,
          indexed_at: nil,
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        ]
      ],
      conflict_target: :postmortem_id
    )

    EmbeddingWorker.enqueue(postmortem.id, content_hash)
    :ok
  end

  defp save_embedding(postmortem_id, content_hash, vector) when is_list(vector) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Embedding{}
    |> Embedding.changeset(%{
      postmortem_id: postmortem_id,
      content_hash: content_hash,
      status: :indexed,
      embedding: vector,
      failure_reason: nil,
      indexed_at: now
    })
    |> Repo.insert(
      on_conflict: [
        set: [
          status: :indexed,
          embedding: vector,
          failure_reason: nil,
          indexed_at: now,
          updated_at: now
        ]
      ],
      conflict_target: :postmortem_id,
      returning: true
    )
  end

  defp embed(body) do
    with {:ok, opts} <- Hive.Agents.embedding_client_opts() do
      {model, opts} = Keyword.pop!(opts, :model)
      ReqLLM.embed(model, body, opts)
    else
      {:error, :llm_not_configured} -> {:error, :embedding_not_configured}
    end
  end

  defp content_hash(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

  defp put_domains(postmortem, attrs) do
    domain_ids =
      attrs
      |> Map.get("domain_ids", Map.get(attrs, :domain_ids, []))
      |> List.wrap()
      |> Enum.reject(&(&1 in [nil, ""]))

    domains = Repo.all(from domain in Domain, where: domain.id in ^domain_ids)

    cond do
      length(domains) != length(Enum.uniq(domain_ids)) ->
        {:error,
         Changeset.add_error(
           Changeset.change(postmortem),
           :domain_ids,
           "contains unknown domains"
         )}

      postmortem.visibility == :public and Enum.any?(domains, &(&1.visibility == :private)) ->
        {:error,
         Changeset.add_error(
           Changeset.change(postmortem),
           :domain_ids,
           "public postmortems can only include public domains"
         )}

      true ->
        postmortem
        |> Repo.preload(:domains)
        |> Changeset.change()
        |> Changeset.put_assoc(:domains, domains)
        |> Repo.update()
    end
  end
end
