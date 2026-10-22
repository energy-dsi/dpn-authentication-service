# Keycloak Helm Chart — DPN Platform

Deploys Keycloak into `ns-dpn-01` over **standard one-way HTTPS**, reachable
through an **internal Azure Load Balancer**.

This is *not* mutual TLS — `KC_HTTPS_CLIENT_AUTH=none`. There is no plaintext
listener at all (`KC_HTTP_ENABLED=false`).

Configuration shape: non-secret `KC_*` options in a ConfigMap, passwords from
Key Vault via the CSI driver, and TLS from a pre-existing in-cluster secret
holding Java keystores.

---

## What gets deployed

| Object | Name | Purpose |
| --- | --- | --- |
| Deployment | `dpn-keycloak` | Keycloak, HTTPS on 8443 |
| Deployment | `dpn-keycloak-postgres` | PostgreSQL persistence backend |
| ConfigMap | `dpn-keycloak-config` | Non-secret `KC_*` options |
| Service (ClusterIP) | `dpn-keycloak` | In-cluster access |
| Service (LoadBalancer) | `dpn-keycloak-service-lb` | Internal LB, VNet only, 8443 |
| Service (ClusterIP) | `dpn-keycloak-postgres` | Database, cluster-internal only |
| PVC | `dpn-keycloak-data` | 10Gi, Keycloak `/opt/keycloak/data` |
| PVC | `dpn-keycloak-postgres-data` | 8Gi, database storage |
| SecretProviderClass | `dpn-keycloak-kv-secrets` | Pulls the four passwords from Key Vault |
| ServiceAccount | `dpn-keycloak` | Identity for both pods; no API token mounted |

---

## TLS

The certificate comes from the pre-existing `dpn-tls` secret in `ns-dpn-01`,
mounted read-only at `/cert`.

**`dpn-tls` is an `Opaque` secret holding Java keystores, not a
`kubernetes.io/tls` secret**:

```
keystore.jks     5920 bytes
truststore.jks   3190 bytes
```

Keycloak reads them directly:

```
KC_HTTPS_KEY_STORE_FILE:    /cert/keystore.jks
KC_HTTPS_TRUST_STORE_FILE:  /cert/truststore.jks
KC_HTTPS_KEY_ALIAS:         <alias of the server key inside keystore.jks>
```

The keystore and truststore passwords come from Key Vault.

### `KC_HTTPS_KEY_ALIAS` must be set

Keycloak aborts at startup if the alias does not exist. It is empty by default
because the alias inside `dpn-tls` is not recorded anywhere in this repo. Find
it with:

```sh
kubectl get secret dpn-tls -n ns-dpn-01 \
  -o jsonpath='{.data.keystore\.jks}' | base64 -d > keystore.jks

keytool -list -keystore keystore.jks \
  -storepass "$(az keyvault secret show --vault-name <<your specific value>> \
    --name KC-HTTPS-KEY-STORE-PASSWORD --query value -o tsv)"
```

then set `config.KC_HTTPS_KEY_ALIAS` in the environment values file.

The deploy pipeline verifies the alias exists, prints the certificate behind it,
and checks its SANs against `KC_HOSTNAME`.

### Hostname

`config.KC_HOSTNAME` defaults to the in-cluster FQDN:

```
https://dpn-keycloak.ns-dpn-01.svc.cluster.local:8443
```

It must be a name the certificate in `keystore.jks` actually carries. A shared
platform certificate often covers a public DNS name rather than the in-cluster
service FQDN — check the SANs (the deploy pipeline prints them) and set
`KC_HOSTNAME` to a name the certificate really carries.

---

## Prerequisites

Four secrets in the environment's Key Vault. The deploy pipeline reads the
required names out of the rendered SecretProviderClass and fails if any is
missing, rather than letting the pod fail with an opaque CSI mount error:

| Key Vault secret | Becomes | Used by |
| --- | --- | --- |
| `KC-DB-PASSWORD` | `KC_DB_PASSWORD` | Keycloak, and PostgreSQL via `POSTGRES_PASSWORD_FILE` |
| `KEYCLOAK-ADMIN-PASSWORD` | `KEYCLOAK_ADMIN_PASSWORD` | Bootstrap admin |
| `KC-HTTPS-KEY-STORE-PASSWORD` | `KC_HTTPS_KEY_STORE_PASSWORD` | Opens `keystore.jks` |
| `KC-HTTPS-TRUST-STORE-PASSWORD` | `KC_HTTPS_TRUST_STORE_PASSWORD` | Opens `truststore.jks` |

Also required: the `dpn-tls` secret in `ns-dpn-01`, the Azure Key Vault Secrets
Store CSI driver, and the namespace itself.

---

## Database

PostgreSQL is bundled in the chart on a retained ReadWriteOnce PVC. The
superuser password is read from the CSI mount via `POSTGRES_PASSWORD_FILE`
rather than the synced Kubernetes secret, which removes the first-install
ordering problem — the CSI driver only creates that secret once a pod has
mounted the SecretProviderClass.

To use a managed database instead, set `postgres.enabled: false` and point
`config.KC_DB_URL` at the server:

```yaml
postgres:
  enabled: false
config:
  KC_DB_URL: jdbc:postgresql://<server>.postgres.database.azure.com:5432/keycloak_db
  KC_DB_USERNAME: keycloak_db_user
```

---

## Service account

Both pods run as a dedicated `dpn-keycloak` ServiceAccount rather than sharing
the namespace's `default`. Neither calls the Kubernetes API, so
`automountServiceAccountToken` is `false`. Key Vault access uses the CSI driver's
managed identity, not this account.

To move to Azure Workload Identity later:

```yaml
serviceAccount:
  annotations:
    azure.workload.identity/client-id: <user-assigned identity client id>
  podLabels:
    azure.workload.identity/use: "true"
```

plus pointing the SecretProviderClass at `clientID` instead of
`useVMManagedIdentity`. A federated credential must exist on the identity first.

---

## Per-environment values

```
values-dev-dpn01.yaml      values-devtest-dpn01.yaml   values-test-dpn01.yaml
values-dev-dpn02.yaml      values-devtest-dpn02.yaml   values-test-dpn02.yaml
values-pdev-dpn01.yaml     values-ptest-dpn01.yaml     values-puat-dpn01.yaml
```

Each sets only what differs: the ACR repository prefix and the Key Vault name,
tenant and CSI managed-identity client ID. `pdev`, `ptest` and `puat` are
single-DPN — there is no `dpn02` variant, and the pipelines block it.

---

## Deploying

Through the CD pipeline:

```
.pipelines/azure-pipelines/cd-pipelines/dpn-keycloak-cd.yaml
```

Manually, for a dry run:

```sh
helm lint charts/keycloak -f charts/keycloak/values-dev-dpn01.yaml

helm upgrade --install dpn-keycloak charts/keycloak \
  --namespace ns-dpn-01 \
  -f charts/keycloak/values-dev-dpn01.yaml \
  --wait --timeout 15m
```

The chart refuses to render if `tlsSecretName` or `KC_DB_URL` is empty, if
`KC_HTTPS_CLIENT_AUTH` is anything but `none`, or if `KC_HTTP_ENABLED` is not
`false` — each would otherwise produce a pod that starts and then fails, or a
deployment that quietly stops matching the stated requirement.

---

## Notes and current limits

- `replicaCount` is 1. Scaling out needs an Infinispan/JGroups cluster
  configuration the chart does not set up.
- Bundled PostgreSQL is a single instance on a ReadWriteOnce PVC with
  `strategy: Recreate`. It is not HA.
- The image is stock upstream Keycloak from ACR. If DPN needs bundled providers
  or a baked-in build layer, point `image.repository` at a custom image.
- Probes target the management interface on port 9000, which inherits the HTTPS
  configuration. Set `probes.enabled: false` if that is unreachable.
