defmodule Hive.InferenceTest do
  use Hive.DataCase, async: true

  alias Hive.Inference
  alias Hive.Inference.ModelBinding
  alias Hive.Inference.Provider
  alias Hive.Inference.Token
  alias Hive.Inference.Usage

  describe "model bindings" do
    test "creates a stable model binding" do
      assert {:ok, %ModelBinding{} = binding} =
               Inference.create_model_binding(%{
                 name: "blick-code-review",
                 upstream_provider: "fireworks-ai",
                 upstream_model: "fireworks-ai/accounts/fireworks/models/kimi-k2p5"
               })

      assert binding.name == "blick-code-review"
      assert binding.upstream_provider == "fireworks-ai"
      assert binding.enabled
    end

    test "requires models.dev provider/model identifiers" do
      assert {:error, changeset} =
               Inference.create_model_binding(%{
                 name: "missing-prefix",
                 upstream_provider: "openai",
                 upstream_model: "gpt-4o-mini"
               })

      assert "must use the models.dev provider/model format, for example openai/gpt-4o-mini" in error_messages(
               changeset,
               :upstream_model
             )
    end

    test "requires the model provider to match the selected provider" do
      assert {:error, changeset} =
               Inference.create_model_binding(%{
                 name: "wrong-provider",
                 upstream_provider: "openai",
                 upstream_model: "anthropic/claude-sonnet-4-5"
               })

      assert "must start with the selected provider, for example openai/model-id" in error_messages(
               changeset,
               :upstream_model
             )
    end
  end

  describe "providers" do
    test "lists configured providers with profile references" do
      on_exit(fn -> Inference.delete_process_config() end)

      Inference.put_process_config(
        providers: %{
          "fireworks-ai" => %{
            "base_url" => "https://api.fireworks.ai/inference/v1/",
            "api_key" => "fw-test",
            "timeout" => "120000"
          }
        }
      )

      _configured_binding = model_binding!()

      _missing_binding =
        model_binding!(
          name: "missing-provider",
          upstream_provider: "missing",
          upstream_model: "missing/missing-model"
        )

      assert [
               %{
                 id: "fireworks-ai",
                 base_url: "https://api.fireworks.ai/inference/v1/",
                 configured?: true,
                 credential_configured?: true,
                 endpoint_configured?: true,
                 profile_count: 1,
                 source: :environment,
                 timeout: 120_000
               },
               %{
                 id: "missing",
                 base_url: nil,
                 configured?: false,
                 credential_configured?: false,
                 endpoint_configured?: false,
                 profile_count: 1,
                 source: :reference,
                 timeout: nil
               }
             ] = Inference.list_provider_configs()
    end

    test "creates runtime providers with encrypted credentials" do
      assert {:ok, %Provider{} = provider} =
               Inference.create_provider(%{
                 key: "unit-runtime-fireworks",
                 base_url: "https://api.fireworks.ai/inference/v1/",
                 api_key: "fw-test",
                 timeout: 120_000
               })

      refute provider.api_key_ciphertext == "fw-test"
      assert Provider.api_key(provider) == "fw-test"

      assert [
               %{
                 id: "unit-runtime-fireworks",
                 base_url: "https://api.fireworks.ai/inference/v1/",
                 configured?: true,
                 credential_configured?: true,
                 endpoint_configured?: true,
                 profile_count: 0,
                 source: :database,
                 timeout: 120_000
               }
             ] = Inference.list_provider_configs()
    end
  end

  describe "tokens" do
    test "creates a plaintext token once and stores only the hash" do
      binding = model_binding!()

      assert {:ok, {%Token{} = token, token_value}} =
               Inference.create_token(binding, %{name: "Repository automation"})

      assert String.starts_with?(token_value, "hinf_")
      refute token.token_hash == token_value

      assert {:ok, %Token{model_binding: %ModelBinding{id: binding_id}}} =
               Inference.authenticate_token(token_value)

      assert binding_id == binding.id
    end

    test "rejects revoked and expired tokens" do
      binding = model_binding!()
      {:ok, {revoked, revoked_value}} = Inference.create_token(binding, %{name: "Revoked"})
      {:ok, _revoked} = Inference.revoke_token(revoked)

      {:ok, {_expired, expired_value}} =
        Inference.create_token(binding, %{
          name: "Expired",
          expires_at: DateTime.utc_now() |> DateTime.add(-60, :second)
        })

      assert Inference.authenticate_token(revoked_value) == :error
      assert Inference.authenticate_token(expired_value) == :error
    end

    test "binds tokens to the verified profile instead of caller supplied attrs" do
      binding = model_binding!()

      other_binding =
        model_binding!(
          name: "other-profile",
          upstream_model: "fireworks-ai/accounts/fireworks/models/other"
        )

      assert {:ok, {%Token{} = token, token_value}} =
               Inference.create_token(binding, %{
                 name: "Repository automation",
                 model_binding_id: other_binding.id
               })

      assert token.model_binding_id == binding.id

      assert {:ok, %Token{model_binding: %ModelBinding{id: binding_id}}} =
               Inference.authenticate_token(token_value)

      assert binding_id == binding.id
    end

    test "token changesets ignore caller supplied owner attrs" do
      binding = model_binding!()

      other_binding =
        model_binding!(
          name: "other-token-profile",
          upstream_model: "fireworks-ai/accounts/fireworks/models/other-token"
        )

      changeset =
        %Token{model_binding_id: binding.id, token_hash: "pending"}
        |> Token.changeset(%{
          name: "Repository automation",
          model_binding_id: other_binding.id
        })

      token = Ecto.Changeset.apply_changes(changeset)

      assert token.model_binding_id == binding.id
      refute Map.has_key?(changeset.changes, :model_binding_id)
    end
  end

  describe "relay requests" do
    test "allows only the bound model name" do
      binding = model_binding!()

      assert Inference.model_allowed?(binding, "blick-code-review")
      assert Inference.model_allowed?(binding, "hive/blick-code-review")
      refute Inference.model_allowed?(binding, "another-model")
    end

    test "rewrites the model and resolves the upstream provider" do
      binding = model_binding!()

      assert {:ok, request} =
               Inference.relay_request(
                 binding,
                 %{"model" => "blick-code-review", "messages" => []},
                 config: [
                   providers: %{
                     "fireworks-ai" => %{
                       "base_url" => "https://api.fireworks.ai/inference/v1/",
                       "api_key" => "fw-test"
                     }
                   }
                 ]
               )

      assert Keyword.fetch!(request, :url) ==
               "https://api.fireworks.ai/inference/v1/chat/completions"

      assert Keyword.fetch!(request, :json)["model"] == "accounts/fireworks/models/kimi-k2p5"
      assert {"authorization", "Bearer fw-test"} in Keyword.fetch!(request, :headers)
    end

    test "resolves runtime providers before environment providers" do
      binding =
        model_binding!(
          upstream_provider: "unit-runtime-precedence",
          upstream_model: "unit-runtime-precedence/accounts/fireworks/models/kimi-k2p5"
        )

      assert {:ok, %Provider{} = _provider} =
               Inference.create_provider(%{
                 key: "unit-runtime-precedence",
                 base_url: "https://runtime.example.com/v1/",
                 api_key: "runtime-token",
                 timeout: 120_000
               })

      assert {:ok, request} =
               Inference.relay_request(
                 binding,
                 %{"model" => "blick-code-review", "messages" => []},
                 config: [
                   providers: %{
                     "unit-runtime-precedence" => %{
                       "base_url" => "https://environment.example.com/v1/",
                       "api_key" => "environment-token"
                     }
                   }
                 ]
               )

      assert Keyword.fetch!(request, :url) == "https://runtime.example.com/v1/chat/completions"
      assert {"authorization", "Bearer runtime-token"} in Keyword.fetch!(request, :headers)
      assert Keyword.fetch!(request, :receive_timeout) == 120_000
    end
  end

  describe "usage" do
    setup do
      on_exit(fn -> Inference.delete_process_config() end)

      Inference.put_process_config(
        providers: %{
          "fireworks-ai" => %{
            "input_cost_per_million" => "9.00",
            "output_cost_per_million" => "9.00"
          }
        }
      )

      :ok
    end

    test "records token usage with estimated cost" do
      binding = model_binding!(input_cost_per_million: "1.00", output_cost_per_million: "2.00")
      {:ok, {token, _token_value}} = Inference.create_token(binding, %{name: "Repository"})

      assert {:ok, usage} =
               Inference.record_usage(
                 binding,
                 token,
                 Req.Response.new(
                   status: 200,
                   body: %{
                     "usage" => %{
                       "prompt_tokens" => 1_000,
                       "completion_tokens" => 2_000,
                       "total_tokens" => 3_000
                     }
                   }
                 )
               )

      assert usage.input_tokens == 1_000
      assert usage.output_tokens == 2_000
      assert usage.total_tokens == 3_000
      assert Decimal.equal?(usage.cost_usd, Decimal.new("0.005"))

      period = {DateTime.add(DateTime.utc_now(), -1, :day), DateTime.utc_now()}

      assert %{
               request_count: 1,
               input_tokens: 1_000,
               output_tokens: 2_000,
               total_tokens: 3_000,
               cost_usd: cost_usd
             } = Inference.usage_summary(binding, period)

      assert Decimal.equal?(cost_usd, Decimal.new("0.005"))

      token_id = token.id

      assert %{^token_id => %{input_tokens: 1_000}} =
               Inference.token_usage_summaries(binding, period)

      assert %{request_count: 1, output_tokens: 2_000} = Inference.usage_summary(token, period)

      assert series = [_entry | _entries] = Inference.usage_series(binding, period, :day)
      assert Enum.any?(series, &(&1.input_tokens == 1_000))
      assert Enum.all?(series, &match?(%DateTime{}, &1.bucket))
    end

    test "usage changesets ignore caller supplied owner attrs" do
      binding = model_binding!()
      {:ok, {token, _token_value}} = Inference.create_token(binding, %{name: "Repository"})

      other_binding =
        model_binding!(
          name: "other-usage-profile",
          upstream_model: "fireworks-ai/accounts/fireworks/models/other-usage"
        )

      {:ok, {other_token, _token_value}} =
        Inference.create_token(other_binding, %{name: "Other repository"})

      changeset =
        %Usage{model_binding_id: binding.id, token_id: token.id}
        |> Usage.changeset(%{
          upstream_provider: binding.upstream_provider,
          upstream_model: binding.upstream_model,
          status: 200,
          input_tokens: 1_000,
          output_tokens: 2_000,
          total_tokens: 3_000,
          cost_usd: Decimal.new("0.005"),
          model_binding_id: other_binding.id,
          token_id: other_token.id
        })

      usage = Ecto.Changeset.apply_changes(changeset)

      assert usage.model_binding_id == binding.id
      assert usage.token_id == token.id
      refute Map.has_key?(changeset.changes, :model_binding_id)
      refute Map.has_key?(changeset.changes, :token_id)
    end

    test "falls back to provider pricing when profile pricing is not configured" do
      binding = model_binding!()
      {:ok, {token, _token_value}} = Inference.create_token(binding, %{name: "Repository"})

      assert {:ok, usage} =
               Inference.record_usage(
                 binding,
                 token,
                 Req.Response.new(
                   status: 200,
                   body: %{
                     "usage" => %{
                       "prompt_tokens" => 1_000,
                       "completion_tokens" => 2_000,
                       "total_tokens" => 3_000
                     }
                   }
                 )
               )

      assert Decimal.equal?(usage.cost_usd, Decimal.new("0.027"))
    end
  end

  defp model_binding!(attrs \\ %{}) do
    {:ok, binding} =
      Inference.create_model_binding(
        Map.merge(
          %{
            name: "blick-code-review",
            upstream_provider: "fireworks-ai",
            upstream_model: "fireworks-ai/accounts/fireworks/models/kimi-k2p5"
          },
          Map.new(attrs)
        )
      )

    binding
  end

  defp error_messages(changeset, field) do
    changeset
    |> traverse_errors(fn {message, _opts} -> message end)
    |> Map.fetch!(field)
  end
end
