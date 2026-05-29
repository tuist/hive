defmodule Hive.AuthTest do
  use ExUnit.Case, async: true

  alias Hive.Auth

  describe "check_domain/2" do
    test "passes when the provider has no allowlist" do
      provider = %{display_name: "Google", allowed_domains: []}

      assert Auth.check_domain(provider, "anyone@example.com") == :ok
    end

    test "passes when the email's domain is in the allowlist" do
      provider = %{display_name: "Google", allowed_domains: ["tuist.dev"]}

      assert Auth.check_domain(provider, "alice@tuist.dev") == :ok
    end

    test "is case-insensitive on the email domain" do
      provider = %{display_name: "Google", allowed_domains: ["tuist.dev"]}

      assert Auth.check_domain(provider, "alice@TUIST.dev") == :ok
    end

    test "rejects when the email's domain is not in the allowlist" do
      provider = %{display_name: "Google", allowed_domains: ["tuist.dev"]}

      assert Auth.check_domain(provider, "alice@example.com") == {:error, :domain_not_allowed}
    end

    test "rejects when the provider is nil (unknown key)" do
      assert Auth.check_domain(nil, "alice@tuist.dev") == {:error, :domain_not_allowed}
    end

    test "rejects when the email is not a string" do
      provider = %{display_name: "Google", allowed_domains: ["tuist.dev"]}

      assert Auth.check_domain(provider, nil) == {:error, :domain_not_allowed}
    end
  end
end
