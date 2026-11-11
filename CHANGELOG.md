# Changelog

**Repository:** `dpn-authentication-service`  
**Description:** `Tracks all notable changes, version history, and roadmap toward 1.0.0 following Semantic Versioning.`

<!-- SPDX-License-Identifier: OGL-UK-3.0 -->

--- 

All notable changes to this repository will be documented in this file.

This project follows **Semantic Versioning (SemVer)** ([semver.org](https://semver.org/)), using the format:

`[MAJOR].[MINOR].[PATCH]`
- **MAJOR** (`X.0.0`) – Incompatible API/feature changes that break backward compatibility.
- **MINOR** (`0.X.0`) – Backward-compatible new features, enhancements, or functionality changes.
- **PATCH** (`0.0.X`) – Backward-compatible bug fixes, security updates, or minor corrections.
- **Pre-release versions** – Use suffixes such as `-alpha`, `-beta`, `-rc.1` (e.g., `2.1.0-beta.1`).
- **Build metadata** – If needed, use `+build` (e.g., `2.1.0+20260314`).

---

## How to Update This Changelog

1. When making changes, update this file under the **Unreleased** section.
2. Before a new release, move changes from **Unreleased** to a new dated section with a version number.
3. Follow **Semantic Versioning** rules to categorise changes correctly.
4. If pre-release versions are used, clearly mark them as `-alpha`, `-beta`, or `-rc.X`.

---

## Release 1.1.1 - November 2026

### Added

- None

### Fixed

- AWS: Config file hot fix for Keycloak configuration - the Keycloak UI client now allows the oauth2-proxy hosts for Jaeger, Perses and OpenSearch Dashboards as redirect URIs and web origins, and documents the shared DPN federator client hosts

### Removed

- None

## Release 1.1.0 - October 2026

### Added

- In Keycloak a new role dpnoperator has been provisioned
- The existing role of dpnadmin has been elevated to have user and role management abilities

### Fixed

- None

### Removed

- None
---
## Release 1.0.0 - September 2026
- Deploys and manages **Keycloak**, the OAuth2 / OIDC identity provider for the
DPN keycloak service, along with its bundled PostgreSQL database. 
- It issues access tokens consumed by the DPN users and internal components
- Customised themes to align with the unified UI Portal

---

## Maintained by the National Energy System Operator (NESO)

Copyright 2026 NESO.  This work is licensed under the Open Government Licence 3.0 (OGL). This work has been developed by NESO using content licensed by the Department for Business and Trade (UK) under the OGL.   
 
Licensed under the Open Government Licence v3.0.

For full licensing terms, [OGL_LICENSE.md](./OGL_LICENSE.md)
