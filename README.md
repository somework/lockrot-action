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
   repository activity — keyed by `composer.lock`, so a repeat run on the same lock file
   makes almost no requests.
4. **Runs lockrot** in `working-directory` with the options you set, from the token in
   `github-token` (the workflow's own `GITHUB_TOKEN` by default) so repository-activity checks on
   github.com are not capped. On another host's runner, set `LOCKROT_GITHUB_TOKEN` instead.
5. **Reports**: with `format: github` (the default) every flagged package becomes an annotation on
   its own line of `composer.lock` in the pull request. Every format also lands in the job summary
   as a table, and the report file path comes back as an output. With `--explain` in `args`, the
   action writes no job summary. With `generate-baseline: true`, the action writes no job
   summary, and the step prints no annotations, because lockrot writes nothing to stdout then.
6. **Exits with lockrot's code** after the cache is saved. `0`: no finding failed `fail-on`, and
   `strict-network` did not trip. `1`: a finding failed `fail-on`, or `strict-network` tripped.
   `2`: lockrot could not run or finish, for an input, configuration or usage error, or a file
   that it could not write. Any other code is a setup failure, and the step fails on it: PHP
   stopped lockrot, for example 255 on a fatal error such as an exhausted `memory_limit`, or the
   process was killed, for example 137 on an out-of-memory kill.

![Job summary with the lockrot findings table](https://lockrot.dev/assets/first-run.png)

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `fail-on` | *(lockrot's own default: `none`)* | Comma-separated values that fail the step, at most one of each kind. A grade: `critical`, `high`, `medium` or `low`, which fails on that grade or a higher one. A flag: `abandoned`, `silent`, `pinned`, `left-behind`, `old-promise`, `stale` or `capped`. A flag fails on itself and on each flag before it in this order. A `vulnerable` value: `vulnerable` (any severity), `vulnerable-medium`, `vulnerable-high` or `vulnerable-critical`, which fails on that severity or a higher one. `unchecked` fails on a finding whose check did not run. `none` stands alone. Example: `left-behind,vulnerable-high`. Empty defers to `LOCKROT_FAIL_ON`, then to `extra.lockrot.fail-on` in the manifest. See [choosing the values](https://lockrot.dev/ci/) |
| `target-php` | *(`LOCKROT_TARGET_PHP`, then `extra.lockrot.target-php`, then `config.platform.php`, then the running PHP)* | PHP version the project runs on. It decides `old-promise`, which branch `left-behind` names, whether an advisory's fix runs on it, the PHP the move check solves at, and whether the lock installs on it. Set it explicitly |
| `format` | `github` | `github` (annotations), `table`, `json`, `sarif`, `gitlab`, `markdown` or `html`. An empty value runs `github`. The action always passes `--format`, so `extra.lockrot.format` does not apply. A `--format` in `args` fails the step before lockrot runs |
| `output` | | Where to write the report, relative to the workspace or absolute. Empty keeps it in a directory of the step's own under `RUNNER_TEMP`, so a later step of the job does not replace it. Either way the path is the `report` output. Before lockrot runs, the action removes a file at the `output` path, so the path holds no file when lockrot writes no report, for example on exit 2. The step fails before lockrot runs when the path names a `composer.json` or `composer.lock`, the manifest or lock that `COMPOSER` names, or a baseline: the `baseline` input, a `--baseline` in `args`, and `extra.lockrot.baseline` in the manifest, else `lockrot-baseline.json`. From lockrot 0.13.0 the action passes the path as `--output`. With `--explain` in `args`, or with an older lockrot, the action copies stdout to the path after a run that exits 0 or 1 |
| `working-directory` | `.` | Directory where lockrot runs, relative to the workspace. It holds `composer.json` and `composer.lock`, unless `COMPOSER` names another manifest. `COMPOSER` is read relative to this directory |
| `dev` | `false` | Also check `packages-dev` (`--dev`) |
| `all` | `false` | Report every checked package, not only flagged ones (`--all`) |
| `baseline` | *(`extra.lockrot.baseline`, then `lockrot-baseline.json`)* | Baseline file to read, relative to `composer.json` (`--baseline`). When empty, an `extra.lockrot.baseline` in `composer.json`, or in the manifest that `COMPOSER` names, replaces the default file `lockrot-baseline.json` |
| `generate-baseline` | `false` | Write this run's findings to the baseline (`--generate-baseline`). The step exits 0 whatever `fail-on` says, 1 only when `strict-network` trips, and 2 when lockrot cannot run or finish. From lockrot 0.13.0 the report file holds the run's report. The step prints no annotations, and the action writes no job summary |
| `strict-network` | `false` | Exit 1 when a run note counts as a network failure. Such a note says that lockrot could not read what it asked for. A Composer repository or a repository host (GitHub, GitLab, Bitbucket) did not answer, answered with an error or stopped at a rate limit. A repository can also list a locked package but return no versions of it. An offline run that finds no cached metadata for a locked package writes such a note too ([run notes](https://lockrot.dev/notes/)) |
| `args` | | Extra lockrot options, split on whitespace. The action passes the `lockrot` command name first, so a value can follow its option after a space (`--explain vendor/package`). From lockrot 0.13.0, a misspelt option, or a word that is no option value, fails the step with exit 2. An older lockrot exits 1 there. A `--format` in `args` fails the step before lockrot runs: set the `format` input instead. A `-d` or `--working-dir` in `args` fails the step before lockrot runs too: set the `working-directory` input instead. The action always passes `--format`, so `--explain=vendor/package` needs `format: table` or `format: json` and exits 2 with any other format. It also exits 2 with `generate-baseline: true`. lockrot takes `--fail-on`, `--baseline` and `--target-php` once only, so one of them in `args` exits 2 when the input of the same name is set |
| `version` | *(pinned in `lockrot.env`)* | lockrot release to run: empty, `latest`, or a version such as `0.2.2` |
| `checksum` | | sha256 the downloaded `lockrot.phar` must have; overrides the pinned or published one |
| `github-token` | `${{ github.token }}` | Token for repository-activity checks on github.com, passed to lockrot as `GITHUB_TOKEN`. Without a token, lockrot asks github.com only about packages already stale on release age, and only up to a budget of them ([anonymous cap](https://lockrot.dev/notes/#repository_activity_anonymous_cap)). A package that it does not ask about carries S10, unless it is marked abandoned, so `fail-on: unchecked` fails on it. lockrot sends the token only from a github.com runner. On GitHub Enterprise Server, GHE.com, Gitea or Forgejo, set `LOCKROT_GITHUB_TOKEN` to a github.com token in the step's or job's `env` instead. A `LOCKROT_GITHUB_TOKEN` in that `env` wins over this input |
| `php-version` | | PHP to install with setup-php before running. Empty uses the runner's PHP when it is 7.4+ |
| `cache` | `true` | Cache Composer repository metadata and lockrot's repository-activity answers from GitHub, GitLab and Bitbucket between runs |
| `summary` | `true` | Add the report, rendered as markdown, to the job summary. With lockrot 0.14.0 or newer the action passes `--markdown-max-bytes=1000000` unless `args` sets it, so lockrot leaves rows out of a larger report to keep within the runner's 1 MB limit. That cap also applies to the report file of `format: markdown`, and to any markdown `--output` file in `args`. With an older lockrot, a summary above 1 MB is skipped. Skipped with `--explain` in `args`, whose explanation is in the report file (and in the step log for `format: table`). Skipped with `generate-baseline: true` |

Every lockrot option not listed here can be passed through `args`. Some options can also live
under `extra.lockrot` in `composer.json` — see the
[configuration reference](https://lockrot.dev/configuration/). An input that is set wins over
`composer.json` and over lockrot's environment variables, except `github-token`. The action passes
that input as `GITHUB_TOKEN`, and lockrot reads `LOCKROT_GITHUB_TOKEN` first. So a
`LOCKROT_GITHUB_TOKEN` in the step's or job's `env` wins over the input. A Composer credential for
github.com, such as `github-oauth` in `auth.json`, wins over both
([which credentials](https://lockrot.dev/internals/#which-credentials)). An input that is empty or `false` passes
nothing, so the next source decides: `dev: false` leaves `extra.lockrot.include-dev: true` in
effect. `format` is the exception. The action needs the format to name, print and rewrite the
report, so it always passes `--format`, and an empty `format` runs `github`.

## Outputs

| Output | Meaning |
|---|---|
| `exit-code` | lockrot's exit code, also when the step fails. Empty when the action fails before it sets the output. Examples are a failed download or sha256 check, an unknown `format`, a line break in an input and a missing lock. The refusals before lockrot runs are examples too: an `output` that names a protected file, and a `--format`, `-d` or `--working-dir` in `args`. A code other than 0, 1 and 2 is a setup failure, such as 255 from a PHP fatal error or 137 from a killed process, and the step fails on it |
| `report` | Path of the report file in the requested format. Without `output`, each step gets a path of its own. The file is missing when lockrot wrote no report in this step, for example on exit 2 |
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

Each annotation takes lockrot's mark for the finding: `error` when its own fact fails `fail-on`,
`notice` when the baseline covers its fact or it is not graded, `warning` otherwise
([how each format marks a finding](https://lockrot.dev/ci/#how-each-format-marks-a-finding)). GitHub renders
a limited number of annotations per step. The log holds every annotation. The job summary holds
the whole report up to the runner's 1 MB limit. Above that limit, lockrot 0.14.0 or newer leaves
rows out of the summary, unless `args` sets a larger `--markdown-max-bytes`. In that case, and
with an older lockrot, the summary holds only a size note.

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
code scanning and are tracked across runs. After an exit 2, `lockrot.sarif` is missing and the upload
fails, because the action removes an earlier file at the `output` path before lockrot runs.

### The whole run as one artifact

```yaml
permissions:
  contents: read

steps:
  - uses: actions/checkout@v7
  - uses: somework/lockrot-action@v1
    id: lockrot
    with:
      target-php: '8.4'
      format: html
      output: lockrot-report.html
  - uses: actions/upload-artifact@v7
    if: always()
    with:
      name: lockrot-report
      path: lockrot-report.html
```

One file, opened from the downloaded artifact with no server and nothing fetched from anywhere: the
report, the release branches behind every finding, the advisories and the baseline comparison, with
the filters and the open package kept in the URL so a link points at what you were looking at. It is
the format for the person who did not run it — a reviewer, or whoever picks the ticket up a week
later. `if: always()` keeps the upload running when `fail-on` has already failed the step. Needs
lockrot 0.10.0 or newer.

The page embeds its renderer, about 600 KB in lockrot 0.14, so even a page for a small lock starts
there. `all: true` adds the release detail of every checked package, not only of the flagged ones.
With it, lockrot 0.14 pages measured 740 KB for a 22-package lock and 2.4 MB for a 210-package
lock.

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
      args: --markdown-max-bytes=65536
  - if: github.event_name == 'pull_request'
    env:
      GH_TOKEN: ${{ github.token }}
      PR: ${{ github.event.pull_request.number }}
      REPORT: ${{ steps.lockrot.outputs.report }}
    run: gh pr comment "$PR" --body-file "$REPORT"
```

GitHub refuses a comment body above 65,536 characters. `--markdown-max-bytes` makes lockrot leave
rows out of a larger report and add a row that counts them, instead of `gh pr comment` failing. It
caps the job summary of the same run too. Needs lockrot 0.14.0 or newer.

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

For a project in `apps/api`, keep the default `working-directory` and name the manifest in
`COMPOSER`:

```yaml
- uses: somework/lockrot-action@v1
  env:
    COMPOSER: apps/api/composer.json
  with:
    target-php: '8.4'
    format: sarif
    output: lockrot.sarif
```

lockrot then runs from the root of the repository and reads `apps/api/composer.lock`. SARIF,
annotations and gitlab output name that path, so code scanning puts each alert on that lock. The
setup step requires the same lock and the cache key hashes it. lockrot reads `extra.lockrot` and
the baseline next to `apps/api/composer.json`. `COMPOSER` is relative to `working-directory`, so
do not combine it with `working-directory: apps/api`. The setup step then looks for
`apps/api/apps/api/composer.lock` and fails with that path.

With `working-directory: apps/api` instead, the action rewrites annotations to
`apps/api/composer.lock`. SARIF and gitlab output are not rewritten. lockrot names the lock
relative to the directory that it ran in, and code scanning reads a relative path against the root
of the repository
([SARIF support for code scanning](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning)).
So the alerts of that setup point at `composer.lock` in the root.

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

A development package is reported the same way, but lockrot halves its whole score. The halving
hides no finding: the lowest score before it is 2, a `low` advisory, and 1 is still `low`. A grade
can drop, so `--fail-on=high` reads a high advisory with a reachable fix in it as `medium`. Add a `vulnerable` value such as
`vulnerable-high` to fail on the advisory's own severity.

## Security

- **Every run verifies what it executes.** The default release is pinned by version *and* sha256 in
  [`lockrot.env`](lockrot.env), committed to this repository and reviewed like any other change; a
  tampered download stops the run. An explicit `version` is verified against the `.sha256` that the
  lockrot release publishes, and `checksum` lets you pin your own.
- **Least privilege.** The action needs `contents: read` only. It reads the workspace and writes
  to it in two cases you ask for: the `output` file and the baseline on `generate-baseline`. For
  `format: github`, the action writes the rewritten `output` file to a temporary file with a unique
  name beside it, and renames that file over the report. The
  token in `github-token` is passed to lockrot, which sends it to `api.github.com` alone; it is
  never used for the download. lockrot keeps the workflow's own token from github.com when the
  runner is on another host.
- **No script injection.** Inputs reach the scripts through environment variables, never through
  template expansion inside `run:` blocks.
- **Pinned dependencies.** The two actions this one uses — `actions/cache` and
  `shivammathur/setup-php` — are pinned by commit SHA, as is everything in this repository's own
  workflows. Dependabot proposes updates after a seven-day cooldown. setup-php is called without a
  token, so it never writes the workflow token into Composer's global `auth.json` for later steps
  to pick up.
- **Network.** `github.com` release assets, the Composer repositories configured in the project
  (`repo.packagist.org` by default), the repository hosts the locked packages come from
  (`api.github.com`, GitLab and `api.bitbucket.org`), and GitHub's own cache service through
  `actions/cache`. On a runner without PHP, setup-php fetches its interpreter from its own release
  assets and the platform's package sources.
- **The metadata cache steers verdicts.** It holds Composer's repository metadata and lockrot's
  repository-activity answers from GitHub, GitLab and Bitbucket. GitHub Actions scopes cache entries to the branch that wrote them, so a pull request
  from a fork cannot feed one to `main`; someone with push access can, which is the same trust as
  pushing a workflow change. The archive itself is verified again right before it runs.
- **`generate-baseline` writes a file.** Where it writes is set by `baseline` or by
  `extra.lockrot.baseline` in the project's manifest, so do not run it on pull requests from
  people you would not let write to the runner. Generate baselines locally or on `main`.
- **Checked on every change**: [zizmor](https://docs.zizmor.sh/), actionlint, shellcheck, hadolint,
  Trivy on the image, bats unit tests and an end-to-end matrix on Ubuntu, Windows and macOS.
  [OpenSSF Scorecard](https://scorecard.dev/viewer/?uri=github.com/somework/lockrot-action) runs weekly.
- Report an issue privately through [`SECURITY.md`](SECURITY.md).

lockrot itself reads `composer.lock` and `composer.json`. It writes the job summary file that the
action asks for, and the baseline on `generate-baseline`. From lockrot 0.13.0 it also writes the
report file, except with `--explain` in `args`. Otherwise the action copies the report there. It never runs the project's own Composer plugins or scripts.

## Versioning

`v1` follows the newest `v1.x.y` release. Pin the full commit SHA to opt out of that:

```yaml
- uses: somework/lockrot-action@<commit sha>   # v1.0.0
```

The [update workflow](.github/workflows/update-lockrot.yml) proposes each new lockrot release as a
change of this action. A lockrot release that changes an exit code, an option or the report goes
out as a minor release of the action. Its changelog marks such a change **Breaking**, as 1.1.0 did
for lockrot 0.13.0. A lockrot release without such a change goes out as a patch release. The lockrot version an action release
pins is in its `lockrot.env`, and the `version` input picks another release at any time. The
[changelog](CHANGELOG.md) lists both.

## Docker image

`ghcr.io/somework/lockrot` — the same verified `lockrot.phar` on the official PHP 8.4 CLI image
with everything a CLI analysis never needs removed and the result flattened to one layer: 16 MB to
pull, 44 MB on disk (the base image is 44 MB and 106 MB). Runs as a non-root user, built for
`linux/amd64` and `linux/arm64`. Tags follow the lockrot version that the action release pins:
`0.14.0`, `0.14` and `latest` for lockrot 0.14.0.

```bash
docker run --rm -v "$PWD:/app:ro" ghcr.io/somework/lockrot:0.14 --target-php=8.4 --fail-on=silent
```

The working directory is `/app`; every lockrot option works as documented. Pass
`-e GITHUB_SERVER_URL` with `-e GITHUB_TOKEN`: lockrot sends `GITHUB_TOKEN` to github.com only when
each of `GITHUB_SERVER_URL` and `GH_HOST` is unset, empty or names github.com, so a runner token of
another host stays on that host. For a github.com token on such a runner, pass `-e LOCKROT_GITHUB_TOKEN`. The metadata cache
lives under `/tmp/composer` — mount a volume there to keep it between runs. Any `--user` works.

GitLab CI, with the findings shown inline in the merge request:

```yaml
lockrot:
  image:
    name: ghcr.io/somework/lockrot:0.14
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
cosign verify ghcr.io/somework/lockrot:0.14.0 \
  --certificate-identity-regexp '^https://github\.com/somework/lockrot-action/\.github/workflows/docker\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
gh attestation verify oci://ghcr.io/somework/lockrot:0.14.0 --owner somework
```

Base-image fixes arrive as Dependabot digest bumps to the Dockerfile; the image is rebuilt on every
release of this action and once a week, so a merged bump reaches the published tags within days. A
rebuild keeps the tag and changes the digest, which is why the signature and attestation are per
digest.

## FAQ

**Why is this not a Docker action?** Pulling an image costs a few seconds and works on Linux runners
only. Downloading one PHAR archive and running it on the PHP already on the runner costs under a
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
authentication. Repository activity is checked on GitHub, GitLab and Bitbucket.

## Contributing

Bug reports and fixes are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). Findings about
lockrot's verdicts belong in [somework/lockrot](https://github.com/somework/lockrot/issues).

## License

MIT — see [`LICENSE`](LICENSE). Written by Igor Pinchuk.
