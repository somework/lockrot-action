# lockrot-action

[![CI](https://github.com/somework/lockrot-action/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/somework/lockrot-action/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/somework/lockrot-action?style=flat-square)](https://github.com/somework/lockrot-action/releases/latest)
[![lockrot](https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsomework%2Flockrot-action%2Fmain%2Flockrot.env&search=LOCKROT_VERSION%3D(.*)&replace=%241&label=lockrot&style=flat-square)](https://github.com/somework/lockrot/releases)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/somework/lockrot-action/badge?style=flat-square)](https://scorecard.dev/viewer/?uri=github.com/somework/lockrot-action)
[![License](https://img.shields.io/github/license/somework/lockrot-action?style=flat-square)](LICENSE)

Runs [lockrot](https://lockrot.dev) in GitHub Actions: finds the packages in `composer.lock` that
quietly stopped being maintained — abandoned, silent for years, pinned to a branch, or promising a
PHP version they were never released against — and turns them into pull-request annotations, a job
summary, SARIF for the Security tab, and an exit code you choose.

```yaml
- uses: somework/lockrot-action@v1
  with:
    target-php: '8.4'
    fail-on: silent
```

One step, nothing to install. Also ships a signed 16 MB [Docker image](#docker-image) for GitLab CI,
other CI systems and local runs.

## Contents

[What one run does](#what-one-run-does) · [Inputs](#inputs) · [Outputs](#outputs) ·
[Recipes](#recipes) · [Security](#security) · [Versioning](#versioning) · [Docker image](#docker-image) ·
[FAQ](#faq)

## What one run does

1. **Downloads the lockrot release this action pins** (see [`lockrot.env`](lockrot.env)) from
   GitHub Releases and checks its sha256 against the hash pinned in the same file. A mismatch stops
   the run before anything executes. `version: latest` or an explicit version is verified against
   the `lockrot.phar.sha256` published with that release instead.
2. **Uses the runner's PHP** when it is 7.4 or newer (Ubuntu and Windows runners), otherwise installs
   the latest stable PHP with [shivammathur/setup-php](https://github.com/shivammathur/setup-php)
   (macOS runners ship none).
3. **Restores the metadata cache** — Composer's repository metadata and lockrot's 24-hour cache of
   GitHub repository activity — keyed by `composer.lock`, so a repeat run on the same lock file
   makes almost no requests.
4. **Runs lockrot** in `working-directory` with the options you set, from the token in
   `github-token` (the workflow's own `GITHUB_TOKEN` by default) so repository-activity checks are
   not capped.
5. **Reports**: with `format: github` (the default) every flagged package becomes an annotation on
   its own line of `composer.lock` in the pull request; every format also lands in the job summary as
   a table, and the report file path comes back as an output.
6. **Exits with lockrot's code** after the cache is saved: `0` clean or below `fail-on`, `1` a finding
   reached `fail-on`, `2` a tool or configuration error.

![Job summary with the lockrot findings table](https://lockrot.dev/assets/first-run.png)

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `fail-on` | *(lockrot's own default: `none`)* | Verdict or priority that fails the step: `none`, `stale`, `old-promise`, `left-behind`, `pinned`, `silent`, `abandoned`, or `low`, `medium`, `high`, `critical` (a priority reads the package's place in the project, so `high` fails on an abandoned direct requirement and passes the same verdict in a transitive dev package). Empty defers to `extra.lockrot.fail-on` in `composer.json` |
| `target-php` | *(`config.platform.php`, else the running PHP)* | PHP version the project targets, for the `old-promise` check. Set it explicitly |
| `format` | `github` | `github` (annotations), `table`, `json`, `sarif`, `gitlab` or `markdown` |
| `output` | | Where to write the report, relative to the workspace or absolute. Empty keeps it under `RUNNER_TEMP`; either way the path is the `report` output |
| `working-directory` | `.` | Directory holding `composer.json` and `composer.lock` |
| `dev` | `false` | Also check `packages-dev` (`--dev`) |
| `all` | `false` | Report every checked package, not only flagged ones (`--all`) |
| `baseline` | *(`lockrot-baseline.json`)* | Baseline file to read (`--baseline`) |
| `generate-baseline` | `false` | Write this run's findings to the baseline and exit 0 (`--generate-baseline`) |
| `strict-network` | `false` | Exit 1 when a Composer repository or GitHub could not be reached |
| `args` | | Extra lockrot options, split on whitespace. A misspelt option fails the step with exit 1 |
| `version` | *(pinned in `lockrot.env`)* | lockrot release to run: empty, `latest`, or a version such as `0.2.2` |
| `checksum` | | sha256 the downloaded `lockrot.phar` must have; overrides the pinned or published one |
| `github-token` | `${{ github.token }}` | Token for GitHub repository-activity checks. Without one, checks are capped at 50 packages |
| `php-version` | | PHP to install with setup-php before running. Empty uses the runner's PHP when it is 7.4+ |
| `cache` | `true` | Cache repository metadata and GitHub responses between runs |
| `summary` | `true` | Add the report, rendered as markdown, to the job summary (skipped above the runner's 1 MB limit) |

Every lockrot option not listed here can be passed through `args`, and everything can also live under
`extra.lockrot` in `composer.json` — see the
[configuration reference](https://lockrot.dev/configuration/). Inputs win over `composer.json`.

## Outputs

| Output | Meaning |
|---|---|
| `exit-code` | lockrot's exit code, also when the step fails |
| `report` | Path of the report file in the requested format |
| `version` | The lockrot version that ran |
| `cache-hit` | `true` when the metadata cache was restored from the exact key |

## Recipes

### Annotate pull requests, fail on what matters

```yaml
name: lockrot
on:
  pull_request:
    paths: [composer.lock, composer.json, lockrot-baseline.json]
  schedule:
    - cron: '0 6 * * 1'   # packages rot while nothing changes; look weekly

permissions:
  contents: read

jobs:
  lockrot:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: somework/lockrot-action@v1
        with:
          target-php: '8.4'
          fail-on: silent
```

Findings at or above `fail-on` are error annotations, other flagged packages warnings. GitHub renders
a limited number of annotations per step; the job summary and the log always hold the whole report.

### SARIF in the Security tab

```yaml
permissions:
  contents: read
  security-events: write

steps:
  - uses: actions/checkout@v7
  - uses: somework/lockrot-action@v1
    id: lockrot
    with:
      target-php: '8.4'
      format: sarif
      output: lockrot.sarif
  - uses: github/codeql-action/upload-sarif@v4
    if: always()
    with:
      sarif_file: lockrot.sarif
```

`if: always()` keeps the upload running when `fail-on` already failed the step. Findings then stay in
code scanning and are tracked across runs.

### A pull-request comment

```yaml
permissions:
  contents: read
  pull-requests: write

steps:
  - uses: actions/checkout@v7
  - uses: somework/lockrot-action@v1
    id: lockrot
    with:
      target-php: '8.4'
      format: markdown
      fail-on: none
  - if: github.event_name == 'pull_request'
    env:
      GH_TOKEN: ${{ github.token }}
      PR: ${{ github.event.pull_request.number }}
      REPORT: ${{ steps.lockrot.outputs.report }}
    run: gh pr comment "$PR" --body-file "$REPORT"
```

### Accept what you have, fail on what arrives

A large project rarely starts clean. Generate a [baseline](https://lockrot.dev/baseline/) once,
commit it, and from then on only new or worsened findings fail the build:

```bash
composer lockrot --target-php=8.4 --generate-baseline     # or the PHAR, or the Docker image
git add lockrot-baseline.json && git commit -m "chore: accept current dependency rot"
```

Every later run with a `lockrot-baseline.json` next to `composer.json` compares against it
automatically; no extra input is needed. The `generate-baseline` input does the same on a runner —
useful in a scheduled job that commits the file through a pull request — but the workspace is
discarded when the job ends, so on its own the file goes nowhere.

### A project in a subdirectory

```yaml
- uses: somework/lockrot-action@v1
  with:
    working-directory: apps/api
    target-php: '8.4'
```

Annotations are rewritten to `apps/api/composer.lock` so they land on the right file. SARIF is
not: lockrot writes `composer.lock` relative to the directory it ran in, and code scanning resolves
that against the checkout root, so a subdirectory project's alerts point at the wrong path there.

### macOS and self-hosted runners

The action installs PHP when the runner has none, so nothing changes. Self-hosted runners need
runner 2.293 or newer for the conditional steps. To pick the version, or to force a fresh install:

```yaml
- uses: somework/lockrot-action@v1
  with:
    php-version: '8.4'
```

### Development dependencies too

```yaml
- uses: somework/lockrot-action@v1
  with:
    dev: 'true'
```

A development package is reported the same way, one priority step lower.

## Security

- **Every run verifies what it executes.** The default release is pinned by version *and* sha256 in
  [`lockrot.env`](lockrot.env), committed to this repository and reviewed like any other change; a
  tampered download stops the run. An explicit `version` is verified against the `.sha256` that the
  lockrot release publishes, and `checksum` lets you pin your own.
- **Least privilege.** The action needs `contents: read` only. It reads the workspace and writes
  to it in two cases you ask for: the `output` file and the baseline on `generate-baseline`. The
  token in `github-token` is passed to lockrot, which sends it to `api.github.com` alone; it is
  never used for the download.
- **No script injection.** Inputs reach the scripts through environment variables, never through
  template expansion inside `run:` blocks.
- **Pinned dependencies.** The two actions this one uses — `actions/cache` and
  `shivammathur/setup-php` — are pinned by commit SHA, as is everything in this repository's own
  workflows. Dependabot proposes updates after a seven-day cooldown. setup-php is called without a
  token, so it never writes the workflow token into Composer's global `auth.json` for later steps
  to pick up.
- **Network.** `github.com` release assets, the Composer repositories configured in the project
  (`repo.packagist.org` by default), `api.github.com`, and GitHub's own cache service through
  `actions/cache`. On a runner without PHP, setup-php fetches its interpreter from its own release
  assets and the platform's package sources.
- **The metadata cache steers verdicts.** It holds Composer's repository metadata and lockrot's
  GitHub responses. GitHub scopes cache entries to the branch that wrote them, so a pull request
  from a fork cannot feed one to `main`; someone with push access can, which is the same trust as
  pushing a workflow change. The archive itself is verified again right before it runs.
- **`generate-baseline` writes a file.** Where it writes is set by `baseline` or by
  `extra.lockrot.baseline` in the project's `composer.json`, so do not run it on pull requests from
  people you would not let write to the runner. Generate baselines locally or on `main`.
- **Checked on every change**: [zizmor](https://docs.zizmor.sh/), actionlint, shellcheck, hadolint,
  Trivy on the image, bats unit tests and an end-to-end matrix on Ubuntu, Windows and macOS.
  [OpenSSF Scorecard](https://scorecard.dev/viewer/?uri=github.com/somework/lockrot-action) runs weekly.
- Report an issue privately through [`SECURITY.md`](SECURITY.md).

lockrot itself reads `composer.lock` and `composer.json` and writes nothing except the baseline, on
`generate-baseline` alone. It never runs the project's own Composer plugins or scripts.

## Versioning

`v1` follows the newest `v1.x.y` release. Pin the full commit SHA to opt out of that:

```yaml
- uses: somework/lockrot-action@<commit sha>   # v1.0.0
```

A new lockrot release becomes a new patch release of this action (proposed automatically by the
[update workflow](.github/workflows/update-lockrot.yml)). The lockrot version an action release
pins is in its `lockrot.env`, and the `version` input picks another release at any time. The
[changelog](CHANGELOG.md) lists both.

## Docker image

`ghcr.io/somework/lockrot` — the same verified `lockrot.phar` on the official PHP 8.4 CLI image
with everything a CLI analysis never needs removed and the result flattened to one layer: 16 MB to
pull, 44 MB on disk (the base image is 44 MB and 106 MB). Runs as a non-root user, built for
`linux/amd64` and `linux/arm64`. Tags follow the lockrot version: `0.2.2`, `0.2` and `latest`.

```bash
docker run --rm -v "$PWD:/app:ro" ghcr.io/somework/lockrot:0.2 --target-php=8.4 --fail-on=silent
```

The working directory is `/app`; every lockrot option works as documented. `GITHUB_TOKEN` can be
passed with `-e GITHUB_TOKEN` and the metadata cache lives under `/tmp/composer` — mount a volume
there to keep it between runs. Any `--user` works.

GitLab CI, with the findings shown inline in the merge request:

```yaml
lockrot:
  image:
    name: ghcr.io/somework/lockrot:0.2
    entrypoint: [""]
  variables:
    COMPOSER_CACHE_DIR: $CI_PROJECT_DIR/.lockrot-cache
    # The image runs as uid 65532; this makes the docker executor's checkout writable to it.
    FF_DISABLE_UMASK_FOR_DOCKER_EXECUTOR: "true"
  cache:
    key: lockrot-$CI_COMMIT_REF_SLUG
    paths: [.lockrot-cache]
  script:
    - lockrot --format=gitlab --target-php=8.4 --fail-on=silent > lockrot-codequality.json
  artifacts:
    when: always
    reports:
      codequality: lockrot-codequality.json
```

Every published image is signed with [cosign](https://docs.sigstore.dev/) through GitHub's OIDC
identity and carries a build-provenance attestation and an SBOM. The signature is stored in the
Sigstore bundle format, which needs cosign 3.0 or newer to verify:

```bash
cosign verify ghcr.io/somework/lockrot:0.2.2 \
  --certificate-identity-regexp '^https://github\.com/somework/lockrot-action/\.github/workflows/docker\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
gh attestation verify oci://ghcr.io/somework/lockrot:0.2.2 --owner somework
```

Base-image fixes arrive as Dependabot digest bumps to the Dockerfile; the image is rebuilt on every
release of this action and once a week, so a merged bump reaches the published tags within days. A
rebuild keeps the tag and changes the digest, which is why the signature and attestation are per
digest.

## FAQ

**Why is this not a Docker action?** Pulling an image costs a few seconds and works on Linux runners
only; downloading a 1.2 MB archive and running it on the PHP already on the runner costs under a
second and works everywhere, including Windows and macOS. A composite action can also wrap the
metadata cache and pick any lockrot release through an input, which a fixed image reference cannot.
The image exists for everything that is not GitHub Actions.

**Does it need Composer or `vendor/`?** No. lockrot reads `composer.lock` and `composer.json`; there is
no install step to wait for.

**What about the plugin?** `composer require --dev somework/lockrot` adds `composer lockrot` to the
project and an install-time summary to `composer update`. The action is for CI that should not
depend on the project's own dependency set; both run the same lockrot. See
[lockrot.dev](https://lockrot.dev).

**Which repositories are read?** The ones configured in the project's `composer.json`, through
Composer's own repository layer — Private Packagist, Satis and mirrors included, with Composer's
authentication. Repository activity is checked on GitHub only.

## Contributing

Bug reports and fixes are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). Findings about
lockrot's verdicts belong in [somework/lockrot](https://github.com/somework/lockrot/issues).

## License

MIT — see [`LICENSE`](LICENSE). Written by Igor Pinchuk.
