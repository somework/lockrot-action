# Changelog

All notable changes to this action are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the action follows
[Semantic Versioning](https://semver.org/): `v1` always points at the newest `v1.x.y`.

## [Unreleased]

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

[Unreleased]: https://github.com/somework/lockrot-action/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/somework/lockrot-action/releases/tag/v1.0.0
