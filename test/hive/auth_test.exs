defmodule Hive.AuthTest do
  use ExUnit.Case, async: false

  alias Hive.Auth

  setup do
    previous = Application.get_env(:hive, :auth)

    on_exit(fn ->
      Application.put_env(:hive, :auth, previous)
    end)
  end

  describe "check_domain/2" do
    test "passes when the provider has no allowlist" do
      put_providers(google: %{display_name: "Google", allowed_domains: []})

      assert Auth.check_domain(:google, "anyone@example.com") == :ok
    end

    test "passes when the email's domain is in the allowlist" do
      put_providers(google: %{display_name: "Google", allowed_domains: ["tuist.dev"]})

      assert Auth.check_domain(:google, "alice@tuist.dev") == :ok
    end

    test "rejects when the email's domain is not in the allowlist" do
      put_providers(google: %{display_name: "Google", allowed_domains: ["tuist.dev"]})

      assert Auth.check_domain(:google, "alice@example.com") == {:error, :domain_not_allowed}
    end

    test "rejects when the provider is unknown" do
      put_providers([])

      assert Auth.check_domain(:google, "alice@tuist.dev") == {:error, :domain_not_allowed}
    end
  end

  defp put_providers(providers) do
    Application.put_env(:hive, :auth, mode: "oidc", providers: providers)
  end
end
