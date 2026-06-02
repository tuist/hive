defmodule Hive.AuthTest do
  use ExUnit.Case, async: true

  alias Hive.Accounts.User
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

  describe "role/2" do
    test "an unauthenticated user is anonymous" do
      assert Auth.role(nil, ["tuist.dev"]) == :anonymous
    end

    test "everyone signed in is a member when no org domains are configured" do
      assert Auth.role(%User{email: "outsider@example.com"}, []) == :member
    end

    test "a matching email domain is a member" do
      assert Auth.role(%User{email: "pedro@tuist.dev"}, ["tuist.dev"]) == :member
    end

    test "a non-matching email domain is an external contributor" do
      assert Auth.role(%User{email: "jane@example.com"}, ["tuist.dev"]) == :contributor
    end

    test "domain matching is case-insensitive" do
      assert Auth.role(%User{email: "Pedro@Tuist.DEV"}, ["tuist.dev"]) == :member
    end
  end
end
