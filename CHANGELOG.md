# Changelog

All notable changes to this action are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the action follows
[Semantic Versioning](https://semver.org/): `v1` always points at the newest `v1.x.y`.

## [Unreleased]

## [1.0.12] - 2026-09-23

### Added

- `fail-on: unchecked` — fail the run when a check a verdict rests on did not run, rather than pass
  over an unasked question. The case it is for is the workflow that never passed `github-token`
  through: anonymously GitHub allows 60 requests an hour, so lockrot asks about the packages that
  already look stale on release age and no others, and a repository archived a week after its last
  release is never seen. That run says `ok` and exits 0, exactly like a run that checked everything.
  With this threshold it exits 1 and the evidence names each missing check and the signals it
  blocked. It is neither a verdict nor a priority, so it composes with neither — pick it when the
  question is "did this run actually check?" rather than "what did it find?". Credentials take away
  the repository-activity reasons and only those: a package whose newest releases are dated by a
  commit their tags share still carries the signal.

### Changed

- Runs lockrot 0.11.0. **`left-behind` now suggests a branch the project can install.** Until now
  S8 named the newest releasing branch and wrote the constraint that follows it whatever PHP that
  branch requires — a project on PHP 7.4 was told `require ^3.12` for a branch needing 8.1, a line
  it cannot write. The suggestion is now held to the project's own `require.php` and the target
  PHP, and where no releasing branch is within reach it says so and suggests nothing. A workflow
  whose annotations or PR comment are read by a person sees different `require ^X` lines, and
  fewer of them; the verdict itself is unchanged, so `fail-on: left-behind` and `fail-on: high`
  fail on the same locks as before.
- One number for how far behind the lock is: libyears, the years between each installed release
  and its package's newest stable one, summed. It prints in the footer of every format, rides in
  `--format=json` per finding and as a block, and shows in the HTML page. It is laid over the
  verdicts and enters no `fail-on`, no priority and no baseline, so nothing in an existing workflow
  changes because of it. A package whose installed tag is dated only by a commit its tags share is
  left unmeasured rather than measured from that commit's date — on a lock full of
  `symfony/polyfill-*` that is several packages counted as unknown instead of as a year or two
  behind.
- `abandoned` says whether there is somewhere to go. Packagist's replacement field is free text, so
  an annotation could read `migrate to Symfony`; it is now printed only where it names a real
  package, and the JSON carries it under `replacement` with the count split in `abandoned`.
  See the [0.11.0 release notes](https://github.com/somework/lockrot/releases/tag/v0.11.0).

## [1.0.11] - 2026-09-22

### Added

- `format: html` — the whole run as one self-contained page, for uploading as an artifact. It
  carries the report, the release branches behind every finding, the advisories and the baseline
  comparison in a single file that opens from the downloaded artifact with no server and nothing
  fetched from anywhere, and the filters and the open package live in the URL, so a link points at
  what the sender was looking at. It is the format for the person who did not run it — a reviewer,
  or whoever picks the ticket up a week later. The report file is named `.html`, so the artifact
  opens as a page rather than as text. `all: true` puts every checked package in it at roughly 4 KB
  each; without it a 100-package lock lands around 250 KB. See
  [the recipe](README.md#the-whole-run-as-one-artifact).

### Changed

- Runs lockrot 0.10.0. **A repository URL no longer carries its credentials into a report.** A
  private Composer source is routinely configured with a token in the URL — `https://gitlab-ci-token:$CI_JOB_TOKEN@…`
  is how GitLab CI hands a job access to one, and Bitbucket app passwords take the same shape — and
  Composer keeps it in the lock because it has to fetch with it. lockrot 0.8.0 and 0.9.0 printed
  that value verbatim in `--explain`, so a workflow that passed `--explain` through `args` put a
  working token wherever the report went: the step log, the job summary, the uploaded file. Every
  repository URL lockrot prints now has its userinfo removed and its host kept. A run that never
  asked for an explanation was not affected.
- The report says what the run was told to do. `--format=json` now opens with a `run` block naming
  the project — from its own `name` in composer.json, or `extra.lockrot.project` where that is not
  the name to publish — along with the target PHP, the thresholds, the `fail-on`, the name of the
  lock and the verdicts the run counted as findings. Until now a report named the target PHP in one
  place only, inside an S5 signal, so a run where S5 never fired left no record of what it aimed at.
  Every finding also carries `baseline`: `known`, `new` or `worsened`, with the verdict the baseline
  accepted. Both are optional under the same schema number, so a step that reads the report keeps
  working. See the [0.10.0 release notes](https://github.com/somework/lockrot/releases/tag/v0.10.0).

## [1.0.10] - 2026-09-21

### Changed

- Runs lockrot 0.9.0. Packages split out of a monorepo are measured again: since 0.8.0 a tag
  sharing its commit with two others was read as undated, which killed a false `left-behind` but
  also silenced a branch that really had stopped. The monorepo's own tag for the same version now
  supplies the date, so a lock on `illuminate/contracts v5.8.36` reads `branch 5.x last released
  2020-08-18 (6.1 years ago, dated by laravel/framework)` where 0.8.0 said nothing — a workflow
  with `fail-on: left-behind` or `fail-on: high` can start failing on a Laravel, Symfony or CakePHP
  lock that passed before. Laravel's late security tags on 6.x, 7.x and 8.x are recent enough that
  those branches still read as current under the default thresholds.
- The JSON the action uploads is a published document now: `--format=json` opens with a `$schema`
  key naming [`report-1.json`](https://lockrot.dev/schema/report-1.json), so a later step can
  validate it with any draft-04 validator, and an editor completes a baseline file as you write it.
  Under one number a document only ever gains fields, and `lockrot.schema` stays `1`, so a step
  that reads the report keeps working. S8 and S2 gain `dated_by`, naming the monorepo that dated
  the branch. See the [0.9.0 release notes](https://github.com/somework/lockrot/releases/tag/v0.9.0).
  The action still pins the PHAR by sha256 in `lockrot.env`; nothing changes in how it runs.

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

[Unreleased]: https://github.com/somework/lockrot-action/compare/v1.0.11...HEAD
[1.0.11]: https://github.com/somework/lockrot-action/compare/v1.0.10...v1.0.11
[1.0.10]: https://github.com/somework/lockrot-action/compare/v1.0.9...v1.0.10
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
