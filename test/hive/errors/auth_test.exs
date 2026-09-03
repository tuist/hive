defmodule Hive.Errors.AuthTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Hive.Errors.Auth

  describe "extract/1" do
    test "reads the key from the X-Sentry-Auth header" do
      conn =
        conn(:post, "/api/1/envelope/", "")
        |> put_req_header(
          "x-sentry-auth",
          "Sentry sentry_version=7, sentry_key=abcdef1234567890abcdef1234567890, sentry_client=sentry.python/1.0"
        )

      assert {:ok, "abcdef1234567890abcdef1234567890"} = Auth.extract(conn)
    end

    test "strips optional surrounding double quotes on values" do
      conn =
        conn(:post, "/api/1/envelope/", "")
        |> put_req_header(
          "x-sentry-auth",
          "Sentry sentry_key=\"quoted-key\", sentry_version=7"
        )

      assert {:ok, "quoted-key"} = Auth.extract(conn)
    end

    test "falls back to the query parameter when no header is set" do
      conn = conn(:post, "/api/1/envelope/?sentry_key=abc-query", "")
      assert {:ok, "abc-query"} = Auth.extract(conn)
    end

    test "returns :missing_key when neither is present" do
      conn = conn(:post, "/api/1/envelope/", "")
      assert {:error, :missing_key} = Auth.extract(conn)
    end
  end

  describe "extract_from_dsn/1" do
    test "extracts the public key from a modern DSN" do
      assert {:ok, "publicabcdef"} =
               Auth.extract_from_dsn("https://publicabcdef@errors.example.com/42")
    end

    test "extracts the public key from a legacy DSN with a secret" do
      assert {:ok, "public"} =
               Auth.extract_from_dsn("https://public:secret@errors.example.com/42")
    end

    test "returns :missing_key for a DSN without credentials" do
      assert {:error, :missing_key} = Auth.extract_from_dsn("https://errors.example.com/42")
    end
  end
end
