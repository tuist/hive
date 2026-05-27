# Hive

Hive is a Phoenix application for orchestrating product work for Tuist.

The project is intentionally minimal while the deployment foundation is being established.

## Production Deployment

Hive production secrets live in the `hive-k8s-production` 1Password vault.

Create a read-only 1Password service account for that vault, then register a
vault-scoped External Secrets store in the Kubernetes cluster:

```bash
kubectl create namespace onepassword --dry-run=client -o yaml | kubectl apply -f -
kubectl -n onepassword create secret generic onepassword-hive-sa-token \
  --from-literal=token="$(op read 'op://Founders/Service Account Auth Token: hive-k8s-production-sa/credential')" \
  --dry-run=client -o yaml | kubectl apply -f -

cat <<'YAML' | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword-hive
spec:
  provider:
    onepasswordSDK:
      vault: hive-k8s-production
      auth:
        serviceAccountSecretRef:
          name: onepassword-hive-sa-token
          namespace: onepassword
          key: token
YAML
```

The vault must contain:

- `kubeconfig: hive-production` document, used by GitHub Actions deploys.
- `hive-secret-key-base/password`, generated with `mix phx.gen.secret`.
- `hive-ghcr-pull/notesPlain`, base64 of a Docker config JSON for GHCR pulls.
- `hive-postgres-backup/username` and `hive-postgres-backup/credential`, used by CNPG backups.
