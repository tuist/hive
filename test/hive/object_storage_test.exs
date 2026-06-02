defmodule Hive.ObjectStorageTest do
  use ExUnit.Case, async: true

  alias Hive.ObjectStorage

  @config %ObjectStorage{
    endpoint_url: "https://fsn1.your-objectstorage.com",
    region: "fsn1",
    bucket: "hive-test",
    access_key_id: "access-key",
    secret_access_key: "secret-key"
  }

  test "put_object signs and stores an object" do
    request = fn request ->
      headers = Map.new(request[:headers])

      assert request[:method] == :put

      assert request[:url] ==
               "https://fsn1.your-objectstorage.com/hive-test/accounts/acme/logo.png"

      assert request[:body] == "image-bytes"
      assert headers["content-type"] == "image/png"
      assert headers["x-amz-content-sha256"] == sha256_hex("image-bytes")
      assert headers["authorization"] =~ "AWS4-HMAC-SHA256 Credential=access-key/"
      assert headers["authorization"] =~ "/fsn1/s3/aws4_request"

      assert headers["authorization"] =~
               "SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date"

      {:ok, %{status: 200, body: "", headers: []}}
    end

    assert {:ok, %{status: 200}} =
             ObjectStorage.put_object("accounts/acme/logo.png", "image-bytes",
               config: @config,
               content_type: "image/png",
               request: request
             )
  end

  test "get_object returns the body and content type" do
    request = fn request ->
      assert request[:method] == :get
      assert request[:url] == "https://fsn1.your-objectstorage.com/hive-test/notes/demo.txt"

      {:ok, %{status: 200, body: "hello", headers: [{"content-type", "text/plain"}]}}
    end

    assert {:ok, %{body: "hello", content_type: "text/plain", key: "notes/demo.txt"}} =
             ObjectStorage.get_object("notes/demo.txt", config: @config, request: request)
  end

  test "delete_object accepts no-content responses" do
    request = fn request ->
      assert request[:method] == :delete
      assert request[:url] == "https://fsn1.your-objectstorage.com/hive-test/notes/demo.txt"

      {:ok, %{status: 204, body: "", headers: []}}
    end

    assert {:ok, %{status: 204}} =
             ObjectStorage.delete_object("notes/demo.txt", config: @config, request: request)
  end

  test "head_object checks object metadata without fetching a body" do
    request = fn request ->
      assert request[:method] == :head
      assert request[:url] == "https://fsn1.your-objectstorage.com/hive-test/notes/demo.txt"

      {:ok, %{status: 200, body: "", headers: [{"content-type", "text/plain"}]}}
    end

    assert {:ok, %{status: 200}} =
             ObjectStorage.head_object("notes/demo.txt", config: @config, request: request)
  end

  test "returns unexpected status errors with the response body" do
    request = fn request ->
      assert request[:method] == :get

      {:ok, %{status: 404, body: "missing", headers: []}}
    end

    assert {:error, {:unexpected_status, 404, "missing"}} =
             ObjectStorage.get_object("notes/missing.txt", config: @config, request: request)
  end

  test "returns request failures" do
    request = fn request ->
      assert request[:method] == :get

      {:error, :timeout}
    end

    assert {:error, :timeout} =
             ObjectStorage.get_object("notes/demo.txt", config: @config, request: request)
  end

  test "public_url returns a configured public base URL when available" do
    config = %{@config | public_base_url: "https://objects.tuist.dev/hive"}

    assert {:ok, "https://objects.tuist.dev/hive/folder/a%20b.txt"} =
             ObjectStorage.public_url("folder/a b.txt", config: config)
  end

  test "public_url falls back to the object URL" do
    assert {:ok, "https://fsn1.your-objectstorage.com/hive-test/folder/a%20b.txt"} =
             ObjectStorage.public_url("folder/a b.txt", config: @config)
  end

  describe "s3_config/1" do
    test "returns disabled when object storage is not enabled" do
      assert ObjectStorage.s3_config(provider: :none) == :disabled
    end

    test "returns the S3 configuration when required fields are present" do
      config = [
        provider: :s3,
        s3: [
          bucket: "hive-objects",
          region: "fsn1",
          endpoint_url: "https://fsn1.your-objectstorage.com",
          access_key_id: "access-key-id",
          secret_access_key: "secret-access-key",
          public_base_url: "https://objects.example.com/hive",
          force_path_style: true
        ]
      ]

      assert ObjectStorage.s3_config(config) ==
               {:ok,
                %{
                  bucket: "hive-objects",
                  region: "fsn1",
                  endpoint_url: "https://fsn1.your-objectstorage.com",
                  access_key_id: "access-key-id",
                  secret_access_key: "secret-access-key",
                  public_base_url: "https://objects.example.com/hive",
                  force_path_style: true
                }}
    end

    test "reports missing required fields when S3 is incomplete" do
      assert ObjectStorage.s3_config(provider: :s3, s3: [bucket: "hive-objects"]) ==
               {:error, {:missing, [:region, :endpoint_url, :access_key_id, :secret_access_key]}}
    end
  end

  defp sha256_hex(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end
end
