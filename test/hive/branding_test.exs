defmodule Hive.BrandingTest do
  use ExUnit.Case, async: true

  use Mimic

  alias Hive.Branding

  describe "product_name/1" do
    test "falls back to Hive when the instance configures no name" do
      assert Branding.product_name() == "Hive"
    end

    test "uses the configured name" do
      assert Branding.product_name(product_name: "Tuist") == "Tuist"
    end

    test "ignores a blank name" do
      assert Branding.product_name(product_name: "   ") == "Hive"
    end
  end

  describe "logo_url/1" do
    test "serves the bundled logo when the instance configures none" do
      assert Branding.logo_url() == "/images/logo.png"
      refute Branding.custom_logo?()
    end

    test "uses the configured logo" do
      opts = [logo_url: "https://example.com/logo.png"]

      assert Branding.logo_url(opts) == "https://example.com/logo.png"
      assert Branding.custom_logo?(opts)
    end
  end

  describe "logo_data_uri/1" do
    test "embeds the bundled logo by default" do
      assert "data:image/png;base64," <> _rest = Branding.logo_data_uri()
    end

    test "fetches a configured logo once and reuses it afterwards" do
      url = unique_url()
      test_pid = self()

      expect(Req, :get, 1, fn ^url, _opts ->
        send(test_pid, :fetched)

        {:ok,
         %Req.Response{
           status: 200,
           headers: %{"content-type" => ["image/svg+xml; charset=utf-8"]},
           body: "<svg />"
         }}
      end)

      data_uri = Branding.logo_data_uri(logo_url: url)

      assert data_uri == "data:image/svg+xml;base64,#{Base.encode64("<svg />")}"
      assert_received :fetched

      assert Branding.logo_data_uri(logo_url: url) == data_uri
    end

    test "falls back to the bundled logo when the configured one can't be fetched" do
      stub(Req, :get, fn _url, _opts -> {:error, %Req.TransportError{reason: :timeout}} end)

      assert "data:image/png;base64," <> _rest = Branding.logo_data_uri(logo_url: unique_url())
    end

    test "falls back to the bundled logo when the configured one answers with an error status" do
      stub(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 404, headers: %{}, body: "not found"}}
      end)

      assert "data:image/png;base64," <> _rest = Branding.logo_data_uri(logo_url: unique_url())
    end
  end

  describe "logo_cache_key/1" do
    test "keys the bundled logo by its contents and a configured logo by its URL" do
      url = "https://example.com/logo.png"

      assert Branding.logo_cache_key(logo_url: url) == url
      assert Branding.logo_cache_key() != url
    end
  end

  defp unique_url, do: "https://example.com/logo-#{System.unique_integer([:positive])}.png"
end
