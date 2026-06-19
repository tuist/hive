defmodule Hive.URLTest do
  use ExUnit.Case, async: true

  alias Hive.URL

  describe "validate_public/1" do
    test "accepts public https URLs" do
      assert {:ok, %URI{}} = URL.validate_public("https://github.com/tuist/hive")
      assert {:ok, %URI{}} = URL.validate_public("http://example.com/path?q=1")
    end

    test "rejects non-http schemes" do
      assert {:error, _} = URL.validate_public("ftp://example.com")
      assert {:error, _} = URL.validate_public("file:///etc/passwd")
      assert {:error, _} = URL.validate_public("javascript:alert(1)")
    end

    test "rejects URLs with credentials" do
      assert {:error, _} = URL.validate_public("https://user:pass@example.com")
    end

    test "rejects non-standard ports" do
      assert {:error, _} = URL.validate_public("https://example.com:8443")
      assert {:error, _} = URL.validate_public("http://example.com:8080")
    end

    test "rejects loopback and private hosts" do
      assert {:error, _} = URL.validate_public("http://localhost")
      assert {:error, _} = URL.validate_public("http://127.0.0.1")
      assert {:error, _} = URL.validate_public("http://10.0.0.1")
      assert {:error, _} = URL.validate_public("http://192.168.1.1")
      assert {:error, _} = URL.validate_public("http://service.internal")
      assert {:error, _} = URL.validate_public("http://metadata.google.internal")
    end

    test "rejects link-local IPs" do
      assert {:error, _} = URL.validate_public("http://169.254.169.254")
    end

    test "rejects non-binary input" do
      assert {:error, _} = URL.validate_public(nil)
      assert {:error, _} = URL.validate_public(123)
    end
  end
end
