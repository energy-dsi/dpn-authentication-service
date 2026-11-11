# GitHub Actions CD

This repo's workflows are self-contained and runnable directly from here — `workflow_dispatch` from the Actions tab, no dependency on any other repo.

- `dpn-gha-keycloak-cd.yaml` — install/deploy.
- `dpn-gha-keycloak-rollback.yaml` — `helm rollback` to a specific or auto-resolved previous revision. Requires typing the release name (`dpn-keycloak`) again to confirm.
- `dpn-gha-keycloak-uninstall.yaml` — `helm uninstall`. Requires the same confirmation. The Postgres PVC is retained by default; pass `deletePvc: true` to also permanently delete it (all realms/users/clients lost) — matches the real ADO `dpn-keycloak-uninstall-cd.yaml` pipeline's `deletePvc` parameter.

## One-time setup required (not a workflow change)

Before the first run, whoever operates this repo on GitHub needs to configure:

- **GitHub Environments** named `<environment>-<cluster>` for each target you'll deploy to (e.g. `dev-dpn01`, `dev-dpn02`, `test-dpn01`, `test-dpn02`) — used for approval gates and environment-scoped secrets.
- **Repository or Environment secrets**:
  - `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` — federated identity credential for the Azure path (OIDC, no client secret needed).
- **AWS path**: assumes the shared hub role (`<<your specific value>>`) via GitHub's own OIDC token, then role-chains into your account's `oidc_github_runner_admin` role — no AWS secret needed, but that role must exist and trust this repo's OIDC subject.
- **Self-hosted runner**: workflows target `runs-on: [self-hosted, vmss]` — a runner with that label must be registered and reachable from this repo (or change `runs-on` to a runner pool you control).
- **Per-environment config**: `.github/config/{aws,azure}/<environment>-<cluster>.json` already contains real target values (AKS/EKS cluster names, Key Vault, etc.) — update these if you're pointing at different infrastructure.

Nothing in the workflow itself needs editing to run it — these are environment/credential setup steps, same as any other GitHub Actions deployment pipeline.
