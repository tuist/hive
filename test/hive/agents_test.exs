defmodule Hive.AgentsTest do
  use Hive.DataCase, async: true

  alias Hive.Agents
  alias Hive.Inference
  alias Hive.Inference.Token
  alias Hive.Repo

  test "returns not configured without a Hive profile or launch config" do
    assert Agents.client_opts([]) == {:error, :llm_not_configured}
    refute Agents.enabled?()
  end

  test "falls back to launch config when no Hive inference profile is selected" do
    assert {:ok, opts} =
             Agents.client_opts(
               api_key: "provider-token",
               model: "anthropic:claude-haiku-4-5",
               base_url: "https://llm.example/v1"
             )

    assert opts[:api_key] == "provider-token"
    assert opts[:model] == "anthropic:claude-haiku-4-5"
    assert opts[:base_url] == "https://llm.example/v1"
  end

  test "uses the Hive inference profile through the model gateway" do
    profile = model_binding!(name: "hive-agent", hive_inference: true)

    assert {:ok, opts} = Agents.client_opts([])

    assert opts[:model] == "openai:hive-agent"
    assert opts[:base_url] == HiveWeb.Endpoint.url() <> "/inference/v1"
    assert String.starts_with?(opts[:api_key], "hinf_")

    assert {:ok, token} = Inference.authenticate_token(opts[:api_key])
    assert token.hive_role == "inference"
    assert token.model_binding.id == profile.id

    stored_token = Repo.get_by!(Token, model_binding_id: profile.id, hive_role: "inference")
    assert stored_token.token_ciphertext
    refute stored_token.token_ciphertext == opts[:api_key]
  end

  test "exposes embedding client options from the Hive embedding profile" do
    _inference_profile = model_binding!(name: "hive-agent", hive_inference: true)
    embedding_profile = model_binding!(name: "hive-embeddings", hive_embedding: true)

    assert {:ok, opts} = Agents.embedding_client_opts()

    assert opts[:model] == "openai:hive-embeddings"
    assert opts[:base_url] == HiveWeb.Endpoint.url() <> "/inference/v1"

    assert {:ok, token} = Inference.authenticate_token(opts[:api_key])
    assert token.hive_role == "embedding"
    assert token.model_binding.id == embedding_profile.id
  end

  defp model_binding!(attrs) do
    {:ok, binding} =
      Inference.create_model_binding(
        Map.merge(
          %{
            upstream_provider: "fireworks-ai",
            upstream_model: "fireworks-ai/accounts/fireworks/models/kimi-k2p5"
          },
          Map.new(attrs)
        )
      )

    binding
  end
end
