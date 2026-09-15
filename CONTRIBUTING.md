# Contributing

## Where things are

| Path | What |
|---|---|
| `action.yml` | The composite action: inputs, outputs, the step list |
| `src/setup.sh` | Resolve the release, download and verify the PHAR, detect PHP |
| `src/run.sh` | Build the command line, run lockrot, print the report, write the job summary |
| `src/common.sh` | Helpers shared by both, and by the unit tests |
| `lockrot.env` | The pinned lockrot version and sha256 — the only place they live |
| `Dockerfile` | The `ghcr.io/somework/lockrot` image |
| `tests/unit` | bats suites with `curl` and `php` stand-ins in `tests/unit/stubs` |
| `tests/fixtures/project` | A three-package project with one `silent` finding, used end to end |
| `.github/workflows` | CI, image publishing, the floating tag, the lockrot update check, Scorecard |

## Running the checks locally

```bash
bats tests/unit                                      # unit tests, no network
shellcheck -x src/*.sh tests/unit/stubs/* tests/unit/helpers.bash
actionlint
uvx zizmor --persona pedantic .
docker run --rm -i -v "$PWD/.hadolint.yaml:/.hadolint.yaml:ro" hadolint/hadolint hadolint - < Dockerfile
```

To drive the scripts by hand the way the runner does, export the variables a composite step gets
(`GITHUB_ACTION_PATH`, `RUNNER_TEMP`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`, `GITHUB_WORKSPACE`)
plus the `INPUT_*` variables listed in `action.yml`, then run `src/setup.sh` and `src/run.sh`.

To build the image:

```bash
set -a; . ./lockrot.env; set +a
docker build --build-arg LOCKROT_VERSION="$LOCKROT_VERSION" --build-arg LOCKROT_SHA256="$LOCKROT_SHA256" -t lockrot .
docker run --rm -v "$PWD/tests/fixtures/project:/app:ro" lockrot --target-php=8.4
```

## Rules of the house

- The scripts stay bash 3.2 compatible (macOS) and must work under Git Bash on Windows.
- Inputs never appear inside a `run:` block as `${{ }}`; they are passed through `env:`.
- Every `uses:` is pinned to a full commit SHA with the version in a trailing comment.
- A new lockrot release changes `lockrot.env` and nothing else; the update workflow does that.
- Changes to what the action does are listed in `CHANGELOG.md` under *Unreleased*.

## Releasing

1. Merge to `main` with `CHANGELOG.md` updated.
2. `gh release create v1.x.y --generate-notes` — the release workflow moves `v1`, and the image
   workflow publishes `ghcr.io/somework/lockrot` for the lockrot version pinned in `lockrot.env`.
