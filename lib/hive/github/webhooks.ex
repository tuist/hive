defmodule Hive.GitHub.Webhooks do
  @moduledoc """
  Verifies GitHub webhook signatures.
  """

  @signature_algorithm "sha256"
  @signature_length 64

  def secret do
    :hive
    |> Application.get_env(:github_app, [])
    |> Keyword.get(:webhook_secret)
    |> case do
      secret when is_binary(secret) ->
        secret = String.trim(secret)

        if secret == "" do
          {:error, :not_configured}
        else
          {:ok, secret}
        end

      _other ->
        {:error, :not_configured}
    end
  end

  def verify_signature(raw_body, signature, secret)
      when is_binary(raw_body) and is_binary(secret) do
    with {:ok, digest} <- parse_signature(signature),
         expected <- signature(raw_body, secret),
         true <- secure_compare(expected, digest) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_signature}
    end
  end

  def verify_signature(_raw_body, _signature, _secret), do: {:error, :invalid_signature}

  defp parse_signature(nil), do: {:error, :missing_signature}

  defp parse_signature(signature) when is_binary(signature) do
    case String.split(String.trim(signature), "=", parts: 2) do
      [algorithm, digest] when algorithm == @signature_algorithm ->
        digest = String.downcase(digest)

        if valid_digest?(digest) do
          {:ok, digest}
        else
          {:error, :invalid_signature}
        end

      _other ->
        {:error, :missing_signature}
    end
  end

  defp parse_signature(_signature), do: {:error, :missing_signature}

  defp signature(raw_body, secret) do
    :hmac
    |> :crypto.mac(:sha256, secret, raw_body)
    |> Base.encode16(case: :lower)
  end

  defp valid_digest?(digest) do
    byte_size(digest) == @signature_length and String.match?(digest, ~r/\A[0-9a-f]+\z/)
  end

  defp secure_compare(left, right) do
    byte_size(left) == byte_size(right) and Plug.Crypto.secure_compare(left, right)
  end
end
