# Changelog

All notable changes to this action are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the action follows
[Semantic Versioning](https://semver.org/): `v1` always points at the newest `v1.x.y`.

## [Unreleased]

## [1.0.4] - 2026-09-16

### Changed

- `fail-on` documents the priority values (`low`, `medium`, `high`, `critical`) lockrot 0.4.0 accepts
  next to the verdicts. No change to what the action runs.

## [1.0.3] - 2026-09-16

### Changed

- Runs lockrot 0.4.0 — repository activity from GitLab and Bitbucket next to GitHub, `fail-on` by
  priority, and a footer that says how old cached activity data is; see the
  [lockrot release notes](https://github.com/somework/lockrot/releases/tag/v0.4.0).

## [1.0.2] - 2026-09-16

### Changed

- Runs lockrot 0.3.0 — transitive exposure: every direct requirement a finding is pulled in by, and
  what each direct requirement pulls in (signal S7); see the
  [lockrot release notes](https://github.com/somework/lockrot/releases/tag/v0.3.0).
- The image build fetches `lockrot.phar` with `ADD --checksum`, so BuildKit refuses a digest mismatch before anything runs; the main branch is protected by a ruleset requiring the CI checks.

## [1.0.1] - 2026-09-16

### Changed

- Action description shortened to the Marketplace limit; README notes that verifying the image signature needs cosign 3.0 or newer.
- Runs lockrot 0.2.2.

## [1.0.0] - 2026-09-16

Runs lockrot 0.2.2.

### Added

- Composite action: verified download of the pinned lockrot release, runner PHP or setup-php when
  none, metadata cache keyed by `composer.lock`, every lockrot option as an input, annotations for
  a subdirectory rewritten to its `composer.lock`, job summary rendered from the offline cache,
  lockrot's exit code applied after the cache is saved.
- Docker image `ghcr.io/somework/lockrot`: 16 MB, non-root, `linux/amd64` and `linux/arm64`,
  cosign-signed with a build-provenance attestation and an SBOM.
- Daily check for a new lockrot release that opens a pull request bumping `lockrot.env`.

[Unreleased]: https://github.com/somework/lockrot-action/compare/v1.0.4...HEAD
[1.0.4]: https://github.com/somework/lockrot-action/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/somework/lockrot-action/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/somework/lockrot-action/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/somework/lockrot-action/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/somework/lockrot-action/releases/tag/v1.0.0
