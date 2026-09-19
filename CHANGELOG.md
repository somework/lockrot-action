# Changelog

All notable changes to this action are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the action follows
[Semantic Versioning](https://semver.org/): `v1` always points at the newest `v1.x.y`.

## [Unreleased]

## [1.0.9] - 2026-09-20

### Changed

- Runs lockrot 0.8.0. The false `left-behind` on packages split out of a monorepo (`illuminate/*`
  on a Laravel lock) is gone: a tag dated only by a commit that two or more other tags share is
  read as undated, so a workflow with `fail-on: left-behind` or `fail-on: high` can pass on a lock
  that failed before. The evidence the annotations and the PR comment carry changes with it: a
  direct `left-behind` row ends `require ^8.2 to follow`, an `abandoned` row with a named
  replacement and an open advisory ends `no fix expected; migrate to symfony/mailer`. The footer
  says why `composer audit` counts more without `--dev`; `--format=json` gains `include_dev` and
  `suggested_constraint` on S8, the `schema` number stays `1`. lockrot's new `--explain` is a
  one-package question for a terminal and has no input here — see the
  [0.8.0 release notes](https://github.com/somework/lockrot/releases/tag/v0.8.0). The action still
  pins the PHAR by sha256 in `lockrot.env`; nothing changes in how it runs.

## [1.0.8] - 2026-09-19

### Changed

- Runs lockrot 0.7.0, which adds the `left-behind` verdict (a quiet release branch under a
  higher branch that keeps shipping) and carries security advisories on the finding, saying which
  release fixes each or that no fix is expected. `fail-on` accepts `left-behind`; a package that
  was `ok`, `stale` or `old-promise` can now be `left-behind` (base priority `high`), and an
  advisory on an `abandoned`, `silent` or `left-behind` package lifts its priority one step, so a
  workflow with `fail-on: high` or `fail-on: critical` can start failing on a lock that passed
  before — see the [0.7.0 release notes](https://github.com/somework/lockrot/releases/tag/v0.7.0).
  The action still pins the PHAR by sha256 in `lockrot.env`; nothing changes in how it runs.

## [1.0.7] - 2026-09-18

### Changed

- Runs lockrot 0.6.1, which restores `phive install somework/lockrot` (the self-update signature
  asset is `lockrot.phar.sig.json` now, so PHIVE no longer mistakes it for a GPG signature). The
  action pins the PHAR by sha256 in `lockrot.env` and never used PHIVE; nothing changes in how it
  runs.

## [1.0.6] - 2026-09-18

### Changed

- Runs lockrot 0.6.0 — a reproducibly built PHAR (rebuild the tag and compare the sha256) whose
  `self-update` now verifies each release's signature with a key built into the archive. The
  action still pins the PHAR by sha256 in `lockrot.env`; nothing changes in how it runs.

## [1.0.5] - 2026-09-17

### Changed

- Runs lockrot 0.5.0 — the first GPG-signed and GitHub-attested PHAR release, and phpstan/phpstan
  is no longer reported `abandoned` (the repository asked about activity is the one the highest
  stable release names, never an older release's). The action still pins the PHAR by sha256 in
  `lockrot.env`; nothing changes in how it runs.

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

[Unreleased]: https://github.com/somework/lockrot-action/compare/v1.0.9...HEAD
[1.0.9]: https://github.com/somework/lockrot-action/compare/v1.0.8...v1.0.9
[1.0.8]: https://github.com/somework/lockrot-action/compare/v1.0.7...v1.0.8
[1.0.7]: https://github.com/somework/lockrot-action/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/somework/lockrot-action/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/somework/lockrot-action/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/somework/lockrot-action/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/somework/lockrot-action/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/somework/lockrot-action/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/somework/lockrot-action/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/somework/lockrot-action/releases/tag/v1.0.0
