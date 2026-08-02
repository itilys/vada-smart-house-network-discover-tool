# AGENTS.md - VaDa Network Discover

This file is the operating guide for humans and AI agents contributing to this
repository. It is intentionally public-safe: do not add private VaDa internal
processes, personal names, local machine paths, customer data, installation
details, screenshots with real network data, credentials, or secrets.

## Purpose

VaDa Network Discover is an open source Swift/macOS utility for discovering
devices on owned or explicitly authorized local networks. It provides a macOS
app, an experimental iPad Simulator build, a Swift core library, and a small
CLI for network inventory and map export.

The project is active and public. Its scope is authorized local-network
discovery only. It is not a vulnerability exploitation, credential testing, or
offensive security tool.

## Repository Status

Status: **active**

Expected work includes:

- macOS app improvements;
- Swift core discovery improvements;
- iPadOS portability work;
- documentation and release hygiene;
- tests for parsing, model behavior, map generation, and scanner boundaries.

## Source of Truth

When documentation conflicts, prefer this order:

1. `README.md` for public product behavior and user-facing instructions.
2. `SECURITY.md` for security policy and responsible-use boundaries.
3. `docs/` for deeper project notes.
4. `Package.swift` for supported platforms, products, and targets.
5. Source code and tests for implemented behavior.
6. `.github/workflows/` for CI/release automation.

If a behavior is not documented, update docs in the same PR when the change is
user-visible or affects contributors.

## Privacy and Public Repository Rules

This is a public open source repository. Before committing, check that the
change does not include:

- personal names, usernames, home directories, or local paths such as
  `/Users/...`, `/private/tmp/...`, or machine-specific folders;
- real customer, installation, supplier, or internal project identifiers;
- real IP inventories, MAC addresses, hostnames, serial numbers, router names,
  Wi-Fi names, exported scan JSON, CSV reports, Mermaid maps, or PNG maps from
  private networks;
- screenshots that reveal network topology, hostnames, MACs, public IPs,
  browser tabs, filesystem paths, or user account details;
- API keys, tokens, certificates, private keys, provisioning profiles, or
  signing credentials;
- private VaDa internal runbooks, deployment paths, or operational details that
  do not apply to this OSS project.

Use synthetic examples in docs and tests. For local-network examples, prefer
clearly generic ranges such as `192.168.1.0/24` and fake names such as
`gateway.local`, `printer.local`, or `solar-controller.local`.

If you need to include an image, create a sanitized mockup or diagram. Mermaid
diagrams are preferred for public documentation because they avoid leaking real
network data.

## Operating Rules

### Do

- Read this file before making changes.
- Keep each change small, scoped, and traceable.
- Use one branch per logical change.
- Open a PR to `main` for feature, fix, or documentation work.
- Keep docs aligned with user-visible behavior.
- State assumptions, risks, and validation clearly.
- Preserve existing SwiftPM structure and project conventions.
- Treat exported scan data as sensitive.

### Do Not

- Do not work directly on `main` unless the maintainer explicitly requests it.
- Do not mix unrelated refactors, fixes, documentation, and features.
- Do not claim tests, builds, UI checks, or release validation you did not run.
- Do not change release, signing, bundle ID, or CI behavior silently.
- Do not add dependencies or network behavior without explaining the reason.
- Do not commit generated bundles, `.build/`, `dist/`, `dist-ios-sim/`, or
  private scan exports.
- Do not add offensive functionality such as exploitation, brute force,
  credential testing, evasion, persistence, or unauthorized remote scanning.

## Branching

Use short, readable branch names tied to one goal:

- `feature/<short-name>` for product or UX work;
- `fix/<short-name>` for bug fixes;
- `docs/<short-name>` for documentation-only work;
- `chore/<short-name>` for maintenance.

Use `/` as the namespace separator. Do not replace it with `-` unless a specific
tooling limitation is documented in the PR.

Examples:

```text
feature/initial-layout-polish
docs/security-guidance
fix/port-parser-range
```

Do not reuse an old branch for a new scope. Keep merged branches on the remote
for auditability and traceability. Do not delete a merged branch unless the
maintainer explicitly requests it.

## Pull Requests

Each PR should include:

- goal;
- scope;
- screenshots or diagrams when UI changes matter, using sanitized data only;
- privacy check;
- risks and assumptions;
- validation performed;
- follow-up work, if any.

Prefer one PR per logical change. If you notice unrelated cleanup while working,
open a separate PR.

Merge policy:

- use the repository owner's preferred merge method;
- keep PRs reviewable and easy to revert;
- retain merged remote branches for auditability and traceability;
- do not rebase or force-push after review has started unless needed and noted.

## Validation Gate

Before calling work done, run the relevant checks:

```bash
swift test --disable-sandbox
scripts/build_app_bundle.sh
scripts/build_ipad_sim_bundle.sh
```

For macOS bundle changes, also verify the built app when possible:

```bash
codesign --verify --deep --strict --verbose=2 "dist/VaDa Network Discover.app"
```

For UI changes:

- verify the first-launch state;
- verify scanned-results state when practical;
- check that text does not clip in the default macOS window;
- use sanitized screenshots if attaching evidence to a PR.

If a check cannot be run, state why in the PR or final report.

## CI/CD

The repository uses GitHub Actions:

- `.github/workflows/ci.yml` runs Swift tests and builds the macOS app bundle on
  pushes and PRs to `main`.
- `.github/workflows/release.yml` builds and publishes a macOS release artifact
  when a `v*` tag is pushed.

There are no self-hosted runners documented for this public repository.

## Dependabot

Status: **missing**

There are currently no third-party Swift package dependencies. Treat Dependabot
or equivalent dependency monitoring as future technical debt if dependencies are
added.

## Release and Distribution Rules

Public releases are cut from tags:

```text
v0.1.0
v0.1.1
v0.2.0
```

The release workflow publishes:

```text
VaDa-Network-Discover-macOS.zip
```

The macOS bundle ID is:

```text
com.vadasmarthouse.networkdiscover
```

The iPad Simulator bundle ID is:

```text
com.vadasmarthouse.networkdiscover.ipad
```

The current release build is ad-hoc signed and not notarized. Do not imply App
Store distribution or Apple notarization unless it has actually been done.

Do not publish a new release tag without confirming version notes, build status,
and release intent with the maintainer.

## Architecture Notes

Important directories:

```text
Sources/
  NetworkDiscoverApp/       SwiftUI macOS/iPadOS app
  NetworkDiscoveryCore/     IPv4 parsing, probes, scanner, models, maps
  netdiscover/              CLI entry point
Tests/
  NetworkDiscoveryCoreTests/
scripts/
  build_app_bundle.sh
  build_ipad_sim_bundle.sh
  install_macos_app.sh
docs/
```

Key implementation facts:

- Network ranges are parsed by `IPv4Network`.
- Scan size is bounded by `ScanConfiguration.maximumHosts`.
- TCP probing uses timeouts and bounded concurrency.
- macOS ping and ARP use `Process` with absolute executable paths and structured
  arguments, not shell interpolation.
- HTTP/HTTPS fingerprinting uses an ephemeral `URLSession`.
- HTTPS trust is intentionally permissive for local inventory metadata only; the
  app does not send credentials.
- JSON, CSV, Mermaid, and PNG exports may contain sensitive network inventory.

## Security Expectations

When changing network behavior, document:

- what traffic is generated;
- whether credentials or secrets are involved;
- timeout and concurrency behavior;
- data written to disk;
- whether exported data could identify a private installation.

Ask before adding:

- authentication flows;
- cloud sync or telemetry;
- public internet scanning defaults;
- background persistence;
- credential storage;
- new signing or release automation.

## Completion Checklist

Before closing a task:

- [ ] correct branch created;
- [ ] one logical change only;
- [ ] privacy check completed;
- [ ] generated/private files excluded;
- [ ] documentation updated if behavior changed;
- [ ] tests/builds run, or limitations explained;
- [ ] PR opened or next step clearly stated;
- [ ] release/deployment status explicitly stated.
