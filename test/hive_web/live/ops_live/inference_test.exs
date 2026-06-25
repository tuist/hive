defmodule HiveWeb.OpsLive.InferenceTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Accounts
  alias Hive.Inference
  alias Hive.Inference.Token
  alias Hive.Repo

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login?return_to=/ops/inference/profiles"}}} =
             live(conn, ~p"/ops/inference")
  end

  test "redirects anonymous visitors away from inference providers", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login?return_to=/ops/inference/providers"}}} =
             live(conn, ~p"/ops/inference/providers")
  end

  test "redirects non-admins away from inference profile management", %{conn: conn} do
    {conn, user} = sign_in(conn, "member@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :member)

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/ops/inference")
  end

  test "redirects non-admins away from inference providers", %{conn: conn} do
    {conn, user} = sign_in(conn, "member-provider@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :member)

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/ops/inference/providers")
  end

  test "redirects non-admins away from inference profile details", %{conn: conn} do
    profile = profile!()
    {conn, user} = sign_in(conn, "member-detail@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :member)

    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/ops/inference/profiles/#{profile.id}")
  end

  test "redirects non-admins away from inference token details", %{conn: conn} do
    profile = profile!()

    {:ok, {%Token{} = token, _token_value}} =
      Inference.create_profile_token(profile, %{name: "Repository"})

    {conn, user} = sign_in(conn, "member-token-detail@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :member)

    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/ops/inference/tokens/#{token.id}")
  end

  test "admins can create profiles from the list and retarget them from the detail page", %{
    conn: conn
  } do
    provider!("fireworks-ai")
    provider!("openai")

    {conn, _user} = log_in_admin(conn, "admin-inference@example.com")

    {:ok, view, html} = live(conn, ~p"/ops/inference/profiles")

    assert html =~ "Profiles"
    assert html =~ "Create profile"
    assert html =~ ~s(id="ops-inference")
    assert html =~ ~s(href="/ops/inference/profiles")
    assert html =~ ~s(href="/ops/inference/providers")
    assert html =~ ~s(id="new-inference-profile-provider")
    assert html =~ ~s(name="profile[upstream_provider]")
    assert html =~ ~s(data-on-value-change="profile_provider_changed")
    assert html =~ ~s(value="fireworks-ai")
    assert html =~ ~s(value="openai")

    html =
      render_hook(view, "profile_provider_changed", %{
        "value" => ["fireworks-ai"]
      })

    assert html =~ ~s(placeholder="fireworks-ai/accounts/fireworks/models/kimi-k2p5")

    html =
      render_submit(view, "create_profile", %{
        "profile" => %{
          "name" => "blick-code-review",
          "description" => "Repository code review profile",
          "upstream_provider" => "fireworks-ai",
          "upstream_model" => "fireworks-ai/accounts/fireworks/models/kimi-k2p5",
          "input_cost_per_million" => "0.15",
          "output_cost_per_million" => "0.60"
        }
      })

    profile = Inference.get_model_binding_by_name("blick-code-review")

    assert html =~ "blick-code-review"
    assert html =~ "Repository code review profile"
    assert html =~ "accounts/fireworks/models/kimi-k2p5"
    assert Decimal.equal?(profile.input_cost_per_million, Decimal.new("0.15"))
    assert Decimal.equal?(profile.output_cost_per_million, Decimal.new("0.60"))

    assert has_element?(
             view,
             ~s(a[href="/ops/inference/profiles/#{profile.id}"]),
             "blick-code-review"
           )

    {:ok, detail, html} = live(conn, ~p"/ops/inference/profiles/#{profile.id}")

    assert html =~ "Configuration"
    assert html =~ "Tokens"
    assert html =~ "Edit profile"
    assert html =~ "Create token"
    assert html =~ "$0.15 / million tokens"
    assert html =~ "$0.60 / million tokens"
    assert html =~ ~s(id="edit-inference-profile-provider")
    assert html =~ ~s(name="profile[upstream_provider]")
    assert html =~ ~s(data-on-value-change="profile_provider_changed")

    html =
      render_hook(detail, "profile_provider_changed", %{
        "value" => ["openai"]
      })

    assert html =~ ~s(placeholder="openai/gpt-4o-mini")

    html =
      render_submit(detail, "update_profile", %{
        "profile" => %{
          "name" => "blick-code-review",
          "description" => "Repository code review profile",
          "upstream_provider" => "openai",
          "upstream_model" => "openai/gpt-4o-mini",
          "input_cost_per_million" => "0.10",
          "output_cost_per_million" => "0.40"
        }
      })

    assert html =~ "openai"
    assert html =~ "gpt-4o-mini"
    assert html =~ "$0.10 / million tokens"
    assert html =~ "$0.40 / million tokens"
  end

  test "admins can review provider configuration", %{conn: conn} do
    _referenced_profile = profile!()

    {:ok, _missing_profile} =
      Inference.create_profile(%{
        name: "missing-provider",
        upstream_provider: "missing",
        upstream_model: "missing/missing-model"
      })

    {conn, _user} = log_in_admin(conn, "admin-inference-providers@example.com")

    {:ok, view, html} = live(conn, ~p"/ops/inference/providers")

    assert html =~ "Providers"
    assert html =~ "Create provider"
    assert html =~ "Credentials are encrypted"
    assert html =~ "fireworks"
    assert html =~ "1 profile"
    assert html =~ "missing"
    assert html =~ "Missing"
    assert html =~ "Not configured"
    assert html =~ ~s(href="/ops/inference/profiles")
    assert html =~ ~s(href="/ops/inference/providers")

    html =
      render_submit(view, "create_provider", %{
        "provider" => %{
          "key" => "anthropic",
          "base_url" => "https://api.anthropic.com/v1",
          "api_key" => "provider-token-test",
          "timeout" => "120000"
        }
      })

    provider = Inference.get_provider_by_key("anthropic")

    assert html =~ "Provider created."
    assert html =~ "anthropic"
    assert html =~ "Ready"
    assert html =~ "Managed in Hive"
    assert html =~ "Configured"
    assert html =~ "120 seconds"
    refute html =~ "provider-token-test"
    refute provider.api_key_ciphertext == "provider-token-test"
  end

  test "admins can create a profile-bound token from profile details", %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "admin-inference-token@example.com")
    profile = profile!()

    {:ok, view, _html} = live(conn, ~p"/ops/inference/profiles/#{profile.id}")

    html =
      render_submit(view, "create_token", %{
        "token" => %{
          "name" => "Repository automation",
          "expires_at" => ""
        }
      })

    assert html =~ "Token created for blick-code-review"
    assert html =~ "Store this token now"

    token_value = token_value_from_html(html)

    assert {:ok, %Token{} = token} = Inference.authenticate_token(token_value)
    assert token.name == "Repository automation"
    assert token.model_binding.id == profile.id
  end

  test "admins revoke profile tokens from token details", %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "admin-inference-revoke@example.com")
    profile = profile!()

    {:ok, {%Token{} = token, token_value}} =
      Inference.create_profile_token(profile, %{name: "Old token"})

    {:ok, view, html} = live(conn, ~p"/ops/inference/profiles/#{profile.id}")
    assert html =~ "Old token"
    refute html =~ ~s(aria-label="Revoke token")
    assert has_element?(view, ~s(a[href="/ops/inference/tokens/#{token.id}"]), "Old token")
    assert {:ok, _token} = Inference.authenticate_token(token_value)

    {:ok, token_view, html} = live(conn, ~p"/ops/inference/tokens/#{token.id}")
    assert html =~ ~s(data-part="revoke-token-card-section")

    render_click(token_view, "revoke_token")

    refute Repo.get!(Token, token.id).enabled
    assert Inference.authenticate_token(token_value) == :error
  end

  test "admins can inspect usage from profile and token details", %{conn: conn} do
    on_exit(fn -> Inference.delete_process_config() end)

    Inference.put_process_config(
      providers: %{
        "fireworks-ai" => %{
          "input_cost_per_million" => "1.00",
          "output_cost_per_million" => "2.00"
        }
      }
    )

    {conn, _user} = log_in_admin(conn, "admin-inference-usage@example.com")
    profile = profile!()

    {:ok, {%Token{} = token, _token_value}} =
      Inference.create_profile_token(profile, %{name: "Tuist repositories"})

    {:ok, _usage} =
      Inference.record_usage(
        profile,
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

    {:ok, profile_view, html} = live(conn, ~p"/ops/inference/profiles/#{profile.id}")

    assert html =~ "Requests"
    assert html =~ "Input tokens"
    assert html =~ "inference-input-tokens-widget"
    assert html =~ "inference-profile-usage-date-range-picker"
    assert html =~ "inference-profile-usage-chart"
    assert html =~ "Input"
    assert html =~ "Output"
    assert html =~ "1,000"
    assert html =~ "2,000"
    assert html =~ "$0.005"

    assert has_element?(
             profile_view,
             ~s(a[href="/ops/inference/tokens/#{token.id}"]),
             "Tuist repositories"
           )

    render_hook(profile_view, "usage_period_changed", %{
      "preset" => "last-7-days",
      "value" => %{}
    })

    assert_patch(
      profile_view,
      "/ops/inference/profiles/#{profile.id}?usage-date-range=last-7-days"
    )

    {:ok, token_view, html} = live(conn, ~p"/ops/inference/tokens/#{token.id}")

    assert html =~ "Tuist repositories"
    assert html =~ "Token bound to"
    assert html =~ "inference-token-usage-date-range-picker"
    assert html =~ "inference-token-usage-chart"
    assert html =~ ~s(data-part="revoke-token-card-section")
    assert html =~ "Revoke token"
    assert html =~ "1,000"
    assert html =~ "2,000"
    assert html =~ "$0.005"

    render_hook(token_view, "usage_period_changed", %{
      "preset" => "last-24-hours",
      "value" => %{}
    })

    assert_patch(
      token_view,
      "/ops/inference/tokens/#{token.id}?usage-date-range=last-24-hours"
    )

    render_click(token_view, "revoke_token")

    refute Repo.get!(Token, token.id).enabled
  end

  defp log_in_admin(conn, email) do
    {conn, user} = sign_in(conn, email)
    {:ok, user} = Accounts.update_user_role(user, :admin)
    {conn, user}
  end

  defp profile! do
    {:ok, profile} =
      Inference.create_profile(%{
        name: "blick-code-review",
        description: "Repository code review profile",
        upstream_provider: "fireworks-ai",
        upstream_model: "fireworks-ai/accounts/fireworks/models/kimi-k2p5",
        input_cost_per_million: "1.00",
        output_cost_per_million: "2.00"
      })

    profile
  end

  defp provider!(key) do
    {:ok, provider} =
      Inference.create_provider(%{
        key: key,
        base_url: "https://#{key}.example.com/v1",
        api_key: "#{key}-token",
        timeout: 300_000
      })

    provider
  end

  defp token_value_from_html(html) do
    [token_value] =
      Regex.run(~r/hinf_[A-Za-z0-9_-]+/, html)

    token_value
  end
end
