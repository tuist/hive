defmodule Hive.ObjectStorageTest do
  use ExUnit.Case, async: true

  alias Hive.ObjectStorage

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
                  force_path_style: true
                }}
    end

    test "reports missing required fields when S3 is incomplete" do
      assert ObjectStorage.s3_config(provider: :s3, s3: [bucket: "hive-objects"]) ==
               {:error, {:missing, [:region, :access_key_id, :secret_access_key]}}
    end
  end
end
