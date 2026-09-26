# README

**Repository:** `dpn-authentication-service`

**Description:** `Deployment assets for the DPN platform's identity provider`

<!-- SPDX-License-Identifier: Apache-2.0 AND OGL-UK-3.0 -->

---

## Overview

This repository contributes to the development of **secure, scalable, and interoperable data-sharing infrastructure**. It supports DSI's mission to enable **trusted, federated, and decentralised** data-sharing across organisations.

This repository is one of several open-source components that underpin DSI's **Data Preparation Node (DPN)**—a framework designed to allow organisations to manage and exchange data securely while maintaining control over their own information. The DPN is actively deployed and tested across multiple sectors, ensuring its adaptability and alignment with real-world needs.

The platform's OAuth2 / OIDC identity provider is **Keycloak**, deployed into the `ns-dpn-01` namespace over standard one-way HTTPS and reachable through an internal Azure Load Balancer. It issues the tokens consumed by the federator gateway, the certificate manager and the management node.

## Prerequisites

* [Helm](https://helm.sh/)
* [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/)
* Access to the target AKS cluster and Azure Key Vault for the environment being deployed

## Configuration & Installation

Detailed configuration and installation instructions for this repository are present in **[dpn-integration-playbook](https://github.com/energy-dsi/dpn-integration-playbook)**

This includes producer/consumer setup, CI/CD pipeline configuration and execution, and deployment validation. Refer to the guide matching your deployment target:

### Azure Deployment

Refer [azure-ado-beta](https://github.com/energy-dsi/dpn-integration-playbook/tree/main/Docs/03-dpn-application-deployment/azure-ado-beta) for Azure specific deployment

## Features

### Keycloak deployment

| | |
| --- | --- |
| Namespace | `ns-dpn-01` |
| In-cluster URL | `https://dpn-keycloak.ns-dpn-01.svc.cluster.local:8443` |
| External access | Internal Azure Load Balancer (`dpn-keycloak-service-lb`), VNet only |
| TLS | Standard one-way HTTPS — **not** mutual TLS (`KC_HTTPS_CLIENT_AUTH=none`) |
| Certificate | `keystore.jks` from the in-cluster `dpn-tls` secret, mounted at `/cert` |
| Plaintext HTTP | Disabled (`KC_HTTP_ENABLED=false`) |
| Database | Bundled PostgreSQL (`dpn-keycloak-postgres`) on a persistent volume |
| Secrets | Azure Key Vault via the Secrets Store CSI driver |

All passwords are read from the environment's Key Vault at runtime and the certificate from an in-cluster secret; nothing sensitive lives in this repository.

See [charts/keycloak/README.md](charts/keycloak/README.md) for prerequisites, the required Key Vault secret names, and the full object inventory.

## Pipelines

**`dpn-keycloak-cd.yaml`** — Validate → Approval → Deploy → Verify.

Validate confirms the required Key Vault secrets exist, verifies the TLS certificate the chart will mount, then runs `helm lint` and a dry run against the target cluster. Deploy runs `helm upgrade --install` and records the deployed image digest as a build artifact. Verify confirms the load balancer really is internal, checks the HTTPS endpoint from inside the cluster, and asserts that plaintext HTTP is refused.

Before the first deploy in an environment, create the two password secrets — see [charts/keycloak/README.md](charts/keycloak/README.md#prerequisites).

**`dpn-keycloak-uninstall-cd.yaml`** — Guard → Approval → Uninstall.

Retains the PostgreSQL PVC by default, so realm data survives a reinstall. Pass `deletePvc: true` to destroy it.

Both pipelines resolve their target from `.pipelines/azure-pipelines/config/<env>-<cluster>.json` and gate on the ADO approval group for the environment (`dsi-dev`, `dsi-devtest` or `dsi-ppd`).

## Public Funding Acknowledgment

This repository has been developed with public funding as part of the Data Sharing Infrastructure (DSI), a UK Government initiative. DSI, alongside its partners, has invested in this work to advance open, secure, and reusable digital twin technologies for any organisation, whether from the public or private sector, irrespective of size.

## License

This repository contains both source code and documentation, which are covered by different licenses:
- **Code:** Licensed under the [Apache License 2.0](./LICENSE.md).
- **Documentation:** Licensed under the [Open Government Licence (OGL) v3.0](./OGL_LICENSE.md).

By contributing to this repository, you agree that your contributions will be licenced under these terms.

See [`LICENSE.md`](./LICENSE.md), [`OGL_LICENSE.md`](./OGL_LICENSE.md) and [`NOTICE.md`](./NOTICE.md) for details.

## Security and Responsible Disclosure

We take security seriously. If you believe you have found a security vulnerability in this repository, please follow our responsible disclosure process outlined in [SECURITY.md](./SECURITY.md).

## Contributing

We welcome contributions that align with the Programme's objectives. Please read our [CONTRIBUTING.md](./CONTRIBUTING.md) guidelines before submitting pull requests.

## Acknowledgements  
This repository has benefited from collaboration with various organisations. For a list of acknowledgments, see [ACKNOWLEDGEMENTS.md](./ACKNOWLEDGEMENTS.md).  

## Support and Contact

For questions, feedback, or support requests:

- Contact DSI team via email to [dsi@neso.energy](mailto:dsi@neso.energy)

## Maintained by the National Energy System Operator (NESO)

Copyright 2026 NESO.  This work is licensed under the Open Government Licence 3.0 (OGL). This work has been developed by NESO using content licensed by the Department for Business and Trade (UK) under the OGL.   
 
Licensed under the Open Government Licence v3.0.

For full licensing terms, [OGL_LICENSE.md](./OGL_LICENSE.md)
