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

  describe "role/1" do
    test "an unauthenticated user is anonymous" do
      assert Auth.role(nil) == :anonymous
    end

    test "returns the user's persisted role" do
      assert Auth.role(%User{role: :collaborator}) == :collaborator
      assert Auth.role(%User{role: :member}) == :member
      assert Auth.role(%User{role: :admin}) == :admin
    end
  end

  describe "member?/1, collaborator?/1, admin?/1" do
    test "member? is true for members and admins" do
      assert Auth.member?(%User{role: :member})
      assert Auth.member?(%User{role: :admin})
      refute Auth.member?(%User{role: :collaborator})
      refute Auth.member?(nil)
    end

    test "collaborator? is true only for collaborators" do
      assert Auth.collaborator?(%User{role: :collaborator})
      refute Auth.collaborator?(%User{role: :member})
      refute Auth.collaborator?(%User{role: :admin})
      refute Auth.collaborator?(nil)
    end

    test "admin? is true only for admins" do
      assert Auth.admin?(%User{role: :admin})
      refute Auth.admin?(%User{role: :member})
      refute Auth.admin?(%User{role: :collaborator})
      refute Auth.admin?(nil)
    end
  end
end
