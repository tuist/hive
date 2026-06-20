defmodule HiveWeb.Plugs.OAuthRegistrationRateLimitTest do
  use HiveWeb.ConnCase, async: true

  alias HiveWeb.Plugs.OAuthRegistrationRateLimit

  describe "call/2" do
    test "allows requests within the window limit" do
      conn = registration_conn()
      opts = rate_limit_opts()

      for _ <- 1..20 do
        refute OAuthRegistrationRateLimit.call(conn, opts).halted
      end
    end

    test "rejects requests over the window limit" do
      conn = registration_conn()
      opts = rate_limit_opts()

      for _ <- 1..20 do
        OAuthRegistrationRateLimit.call(conn, opts)
      end

      conn = OAuthRegistrationRateLimit.call(conn, opts)

      assert conn.halted

      assert json_response(conn, 429) == %{
               "error" => "rate_limited",
               "error_description" => "Too many OAuth client registration requests."
             }
    end

    test "prunes expired buckets" do
      conn = registration_conn()
      identifier = client_identifier(conn)

      OAuthRegistrationRateLimit.call(conn, rate_limit_opts(-10))
      assert :ets.lookup(OAuthRegistrationRateLimit, {identifier, -10}) != []

      OAuthRegistrationRateLimit.call(conn, rate_limit_opts(-7))

      assert :ets.lookup(OAuthRegistrationRateLimit, {identifier, -10}) == []
      assert :ets.lookup(OAuthRegistrationRateLimit, {identifier, -7}) != []
    end
  end

  defp registration_conn do
    Plug.Test.conn(:post, "/oauth2/register")
    |> Map.put(:remote_ip, {127, 255, rem(System.unique_integer([:positive]), 255), 1})
  end

  defp rate_limit_opts(bucket \\ System.unique_integer([:positive, :monotonic])) do
    OAuthRegistrationRateLimit.init(now: fn -> bucket * 60 end)
  end

  defp client_identifier(conn) do
    conn.remote_ip
    |> Tuple.to_list()
    |> Enum.join(".")
  end
end
