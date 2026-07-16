defmodule Hive.Forage.CodingRuns.Sandboxes.KubernetesClient do
  @moduledoc false

  @sandbox_api_version "agents.x-k8s.io/v1beta1"

  def connect(%{conn: conn}) when not is_nil(conn), do: {:ok, conn}

  def connect(%{in_cluster: true}) do
    case K8s.Conn.from_service_account() do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, {:kubernetes_connection_failed, reason}}
    end
  end

  def connect(%{kubeconfig: path} = config) when is_binary(path) and path != "" do
    options =
      case Map.get(config, :context) do
        context when is_binary(context) and context != "" -> [context: context]
        _other -> []
      end

    case K8s.Conn.from_file(path, options) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, {:kubernetes_connection_failed, reason}}
    end
  end

  def connect(_config), do: {:error, :kubernetes_connection_not_configured}

  def create_sandbox(conn, manifest) do
    case manifest |> K8s.Client.create() |> K8s.Client.run(conn) do
      {:ok, _sandbox} -> :ok
      {:error, %K8s.Client.APIError{reason: "AlreadyExists"}} -> :ok
      {:error, %{status: 409}} -> :ok
      {:error, reason} -> {:error, {:kubernetes_sandbox_create_failed, reason}}
    end
  end

  def get_sandbox(conn, namespace, name) do
    operation =
      K8s.Client.get(@sandbox_api_version, "Sandbox", namespace: namespace, name: name)

    case K8s.Client.run(conn, operation) do
      {:ok, sandbox} -> {:ok, sandbox}
      {:error, %K8s.Client.APIError{reason: "NotFound"}} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, {:kubernetes_sandbox_get_failed, reason}}
    end
  end

  def delete_sandbox(conn, namespace, name) do
    operation =
      K8s.Client.delete(@sandbox_api_version, "Sandbox", namespace: namespace, name: name)

    case K8s.Client.run(conn, operation) do
      {:ok, _sandbox} -> :ok
      {:error, %K8s.Client.APIError{reason: "NotFound"}} -> :ok
      {:error, %{status: 404}} -> :ok
      {:error, reason} -> {:error, {:kubernetes_sandbox_delete_failed, reason}}
    end
  end
end
