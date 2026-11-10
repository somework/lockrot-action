# Changelog

All notable changes to this action are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the action follows
[Semantic Versioning](https://semver.org/): `v1` always points at the newest `v1.x.y`.

## [Unreleased]

Runs lockrot 0.14.0. Read the **Breaking:** entries if your workflow keeps a baseline, gates on
`fail-on`, reads the report, passes `args` or reads the default report path. The full list of
lockrot changes is in the [0.14.0 release notes](https://github.com/somework/lockrot/releases/tag/v0.14.0).

### Changed

- **Breaking:** lockrot 0.14 reads baseline-2 only, and a baseline-1 file exits 2, which fails the
  step. So no check run shows findings while the baseline-1 file is in place. Action, in this
  order:
  1. Move the baseline-1 file aside, for example with `git mv`, and push. When the `baseline` input,
     a `--baseline` in `args` or `extra.lockrot.baseline` names the file, remove that setting in
     the same commit. A run without the file that it names exits 2. Without these settings,
     lockrot reads a `lockrot-baseline.json` beside the manifest, so move that file aside too.
  2. Read the findings of the next run. It has no baseline, so a `fail-on` gate can fail.
  3. In one commit, set `generate-baseline: true`, add the upload step of the
     [README baseline recipe](README.md#accept-what-you-have-fail-on-what-arrives), and put back
     a setting that you removed. The run on that commit writes a baseline-2 file, and
     `known_since` starts again on that day. Until you commit the new file, a run on that commit
     without `generate-baseline: true` exits 2 when a setting names the file. Without such a
     setting, that run reads no baseline, so a `fail-on` gate can fail it with exit 1. A run with
     `generate-baseline: true` ignores `fail-on`.
  4. Download the file from the run page, and commit it at the path where the step wrote it.
     Remove `generate-baseline: true` and the moved baseline-1 file.

  The [baseline steps of the 0.14 upgrade page](https://lockrot.dev/changes/0.14/#baselines) have
  the commands.
- **Breaking:** the verdict is a grade (`critical` … `low`, or `ok`, `finished` or `unknown` at 0)
  scored from the flags, and a finding lists every flag that fired. A counted advisory flags the
  package `vulnerable`, and the new flag `capped` marks a release that stops below the newest PHP
  minor that the root allows. So a `fail-on` gate can fail where lockrot 0.13 passed. Action: run
  once with `fail-on: none`, compare the findings, then set the gate.
- **Breaking:** `fail-on: unchecked` also fails when lockrot did not read the advisories or an
  advisory's release data, and when it cannot ask a repository host. It also fails on a package
  from vcs or of an unknown origin. Action: follow the `unchecked` entry of the lockrot 0.14.0
  release notes, or drop `unchecked` from `fail-on`.
- **Breaking:** the reports change. `format: json` and the page of `format: html` carry report-2.
  SARIF and gitlab output hold one record per flag, and SARIF also one per advisory. A
  `format: github` annotation title reads `lockrot: <verdict> — <flags>`. Action: in a step that
  reads a json report, check `."$schema" == "https://lockrot.dev/schema/report-2.json"` first. In
  SARIF, check `runs[0].properties.lockrot_schema == 2`. Key an annotation on its file and line,
  not on its title.
- **Breaking:** lockrot 0.14 sends `GITHUB_TOKEN`, and so the `github-token` input, to github.com
  only when each of `GITHUB_SERVER_URL` and `GH_HOST` is unset, empty or names github.com. On
  GitHub Enterprise Server, GHE.com, Gitea or Forgejo, and on a github.com runner whose `env` sets
  `GH_HOST` to another host, the run is anonymous on github.com, unless Composer holds a
  github.com credential. lockrot says so only with `-v`, so the action then prints one notice that
  names `LOCKROT_GITHUB_TOKEN`. Action: set `LOCKROT_GITHUB_TOKEN` to a github.com token in
  the step's or job's `env`. The action does not pass the input as `LOCKROT_GITHUB_TOKEN`, because
  it cannot tell which host issued the token. The `github-token` texts and the README say so.
- **Breaking:** without `output`, each action step writes its report in a directory of its own
  under `RUNNER_TEMP`, so a later step of the same job no longer replaces it. The old default path
  was `RUNNER_TEMP/lockrot/report.<ext>`. Action: read the path from the `report` output.
- **Breaking:** the step fails before lockrot runs when `output` names a `composer.json` or
  `composer.lock`, the manifest or lock that `COMPOSER` names, or a baseline. The baselines are the
  `baseline` input, a `--baseline` in `args`, and `extra.lockrot.baseline` in the manifest, else
  `lockrot-baseline.json`. The check follows symlinks and `..`, and compares a missing file in any
  letter case. It also refuses a file name that ends in a dot or a space or holds a colon, as
  lockrot does. Windows reads such a name as another file. With `--explain` in `args`, such a path got the explanation copied over the file,
  and `output: composer.lock` or the baseline path emptied that file before lockrot read it. The step
  also fails when PHP cannot read `extra.lockrot.baseline` for this check, or when the check cannot
  enter `working-directory`. It warned and went on. Action: set
  `output` to another path.
- **Breaking:** once the `output` checks pass, the action removes a file at the `output` path
  before lockrot runs, a symlink itself and not its target. A symlink at the path is then replaced
  by a regular file. v1.1.0 redirected stdout into the path, so it wrote through a symlink into
  its target. When lockrot 0.13.0 or newer writes no report, for example on exit 2 or under
  `LOCKROT_DISABLE`, the path holds no file. v1.1.0 left an empty file there, so an
  `if: always()` upload of the path now fails. With `--explain` in `args`, an empty stdout is not
  copied to the path. A lockrot older than 0.13.0 that exits 0 or 1 with an empty stdout still
  leaves an empty file. A step that fails before these checks leaves the earlier file. A directory
  at the path fails the step with `could not remove the earlier report at <path>`. Action: keep no
  file of your own at the `output` path. Let a failed upload stand, or guard it with `hashFiles()`.
- **Breaking:** the step that installs PHP with setup-php clears `GITHUB_TOKEN` and
  `COMPOSER_TOKEN` in its own environment. The action gives setup-php no token, and setup-php then
  took a token from the job's `env` and wrote it into Composer's global `auth.json` as `github-oauth`.
  Later steps then read it, and lockrot sent it instead of the `github-token` input. The step also
  passes `tools: composer`, so a `TOOLS` in the job's `env` no longer adds tools to it. Such a
  `TOOLS` also no longer picks the Composer version that later steps get, such as `composer:2.2`.
  The step installs the default stable Composer. Action: give a later Composer step its own
  credential, for example with `COMPOSER_AUTH`. Install other tools or another Composer version
  with a setup-php step of your own.
- The job summary comes from the same lockrot run as the report. With lockrot 0.13.0 or newer,
  the run writes the markdown summary beside it with `--output`. The action no longer runs
  lockrot a second time offline. The summary now shows that run's own notes, an offline note included when
  the run was offline. With an older lockrot `version`, the second run stays. With `--explain`
  in `args`, the action writes no job summary: lockrot refuses `--output` there, and a second
  offline run showed a whole report whose advisories and gate line could differ from the step.
  The explanation is in the report file, and in the step log for `format: table`.
- **Breaking:** the action passes `lockrot` as the command name before the options. A value can
  follow its option after a space in `args`, such as `--explain vendor/package`. From lockrot
  0.13.0, a word in `args` that is no option value exits 2. It named another command, such as
  `self-update`, or none. Action: remove the word, or put its option before it.
- With lockrot 0.13.0 or newer, the action writes the report of `format: github`, `table` or
  `markdown` through `--output=<format>:<path>`. It no longer uses a shell redirection. Under
  `generate-baseline`, every format goes through `--output`, and the report file holds the run's
  report. So does a run with `--generate-baseline`, a quiet option, `--help` or `--version` in
  `args`, which keeps the report off stdout. For `format: json`, `sarif`, `gitlab` or `html`, lockrot renders the report once, to
  stdout. The action moves stdout to the path after a run that exits 0 or 1, as with `--explain`
  in `args` or an older lockrot. PHP then writes its own messages, such as a startup warning, to stderr, so they cannot reach the
  document. lockrot refuses `--output` with `--explain`.
- The action keeps its own temporary files in a directory of each run under `RUNNER_TEMP`, so no
  `output` path can name one of them.
- **Breaking:** with lockrot 0.14.0 or newer and the job summary on, the action passes
  `--markdown-max-bytes=1000000` unless `args` sets it. lockrot then leaves rows out of a large
  summary, where the action wrote only a size note. The size also applies to the report file of
  `format: markdown`, and to any markdown `--output` file in `args`. It is a target, not a hard
  cap: lockrot leaves out table rows only, so every other part of the report always prints. A
  summary file that is still larger than 1 MB becomes the size note. Action: to keep a whole markdown
  file, set `--markdown-max-bytes` in `args`, or set `summary: false`.
- The `fail-on` input describes the lockrot 0.14.0 values: a comma-separated list of a grade, a
  flag (`capped` included), a `vulnerable` value and `unchecked`, or `none`. It links the
  [CI page](https://lockrot.dev/ci/) for choosing them.
- The `args` input says that `--explain` needs `format: table` or `format: json`, because the
  action always passes `--format`, and that `--explain` exits 2 with `generate-baseline: true`.
- **Breaking:** a `--fail-on`, `--baseline` or `--target-php` in `args` exits 2 when the input of
  the same name is set. The action passes that input as the same option, and lockrot 0.14 refuses
  an option that is given twice. lockrot 0.13 used the value in `args`. The `args` input says so.
  Action: set the value in the input or in `args`, not in both.
- **Breaking:** a `--format` in `args` fails the step before lockrot runs, with an error that names
  the `format` input. It replaced the format that the action prints, names and rewrites the report
  by. Action: set the `format` input.
- **Breaking:** a `-d` or `--working-dir` in `args`, in any spelling, fails the step before lockrot
  runs, with an error that names the `working-directory` input. It moved the project away from the
  files that the action checks and annotates, so an `output` in the other directory could
  overwrite its baseline. Action: set the `working-directory` input.

### Fixed

- On a macOS runner without PHP, the action installs PHP with shivammathur/setup-php 2.40.0. With
  2.37.2, setup-php ran for about 30 minutes and then failed with `Could not setup PHP 8.5`
  ([shivammathur/setup-php#1125](https://github.com/shivammathur/setup-php/issues/1125)). 2.40.0
  writes Composer's `auth.json` as 2.37.2 did, so the step still clears `GITHUB_TOKEN` and
  `COMPOSER_TOKEN` for setup-php.
- The `exit-code` and `report` outputs are set before the action moves the report and appends
  the job summary. A report that the action cannot move to the `output` path fails the step with
  an error that names the path. A job summary file that takes no append gives an error that names
  it, and the step still ends with lockrot's exit code. In v1.1.0 such a summary was skipped
  without a message, and a size note that took no append failed the step with a bash error.
- The `exit-code` output and the README say that a code other than 0, 1 and 2 is a setup failure.
  Examples are 255 from a PHP fatal error and 137 from a killed process. The step fails on it, and its
  warning says so.
- The `cache` input and the README say that the cache holds lockrot's repository-activity answers
  from GitHub, GitLab and Bitbucket, not from GitHub alone.
- With `--explain` in `args`, the log line for the skipped job summary names the place of the
  explanation. That is the report file, and also the step log for a format that the step prints.
- With `format: github` and a `working-directory` other than the root, the annotation rewrite
  writes its copy to a temporary file with a unique name beside the report. It keeps the report's
  mode and renames the copy over the report. It wrote and removed `<output>.tmp`, so a directory
  of that name failed the step without the `exit-code` and `report` outputs. A rewrite that fails
  now stops the step with an error, sets the `exit-code` output and leaves the report as lockrot
  wrote it.
- The `working-directory` texts say that lockrot runs there and that `COMPOSER` is read relative
  to it. A `COMPOSER` path that repeats `working-directory` fails the setup step with the doubled
  lock path.
- A `format` input of whitespace only runs `github`, as an empty one does. It failed the step.
- The README recipe for a project in a subdirectory sets `COMPOSER: apps/api/composer.json` with
  the default `working-directory`. SARIF, annotations and gitlab output then name
  `apps/api/composer.lock`.
- The README and the `format` input say that the action always passes `--format`, so an empty
  `format` runs `github` and `extra.lockrot.format` does not apply.
- The `baseline` texts say that `extra.lockrot.baseline` replaces the default file.
- The `exit-code` output texts say that the output is empty when the action fails before it sets
  the output.
- The `strict-network` texts also name an error answer, a rate limit, and a repository that lists
  a locked package with no versions.
- An option value after a space in `args` no longer exits 1, which the `exit-code` output names
  as a finding that failed `fail-on`. A misspelt option followed by a value exits 2.
- With `format: markdown`, the job summary keeps the run's own offline note, as with the other
  formats.
- The version check reads the last line of stdout only, so a PHP startup warning no longer fails
  the step.
- The `generate-baseline`, `strict-network` and `exit-code` texts state lockrot's exit codes:
  `generate-baseline` exits 1 when `strict-network` trips, and `strict-network` counts every run
  note that is a network failure.
- The `target-php` texts name `LOCKROT_TARGET_PHP` and `extra.lockrot.target-php` before
  `config.platform.php`. The README says that an empty or `false` input passes nothing, so
  `dev: false` leaves `extra.lockrot.include-dev` in effect.
- The README states the lockrot 0.14 html page size and the halved score of a development
  package. It names the Docker image tag of lockrot 0.14, and which lockrot releases make a minor
  release of the action. The pull-request comment recipe caps the comment with `--markdown-max-bytes`.
- A lockrot run that exits 0 or 1 without writing the job summary, such as one with
  `LOCKROT_DISABLE=1`, no longer fails the step. The action skips the summary and sets the
  `exit-code` and `report` outputs. It failed with a bash error and set no output.
- The README Docker section passes `-e GITHUB_SERVER_URL` with `-e GITHUB_TOKEN`, as lockrot 0.14
  needs to keep another host's token from github.com.
- The README and the inputs state lockrot 0.14 facts: repository activity is read on GitHub,
  GitLab and Bitbucket. An annotation takes lockrot's mark, so a finding whose fact the baseline
  covers is a notice. lockrot writes the job summary file that the action asks for. `target-php`
  also decides the `left-behind` branch, the advisory fix, the move check and the PHP window.

- With `COMPOSER` set in the job's environment, the action reads the lock that Composer pairs
  with it: `alt.json` gives `alt.lock`. The setup step requires that lock, the cache key hashes
  it, and its annotations get the `working-directory` prefix. An absolute `COMPOSER` outside
  `working-directory` leaves the annotations as lockrot writes them. The action required and
  hashed `composer.lock` whatever `COMPOSER` named.
- A `working-directory` that does not exist, or that the step cannot enter, fails the setup step. With an absolute `COMPOSER`
  whose lock exists, the run step failed instead and set `exit-code` to 1, although lockrot never
  ran.
- An annotation path keeps a comma, colon or percent sign in `working-directory` or in the lock
  name. The action escapes the directory and matches the lock as lockrot writes workflow-command
  properties. Such a `file=` value ended at the comma, or kept no directory prefix.
- The README and the `generate-baseline` and `summary` inputs say that `generate-baseline: true`
  prints no annotations and writes no job summary. The README no longer says that the job
  summary always holds the whole report.
- The `github-token` texts say what lockrot asks without a token: only packages already stale on
  release age, up to a budget. Each other package carries S10, unless it is marked abandoned,
  and `fail-on: unchecked` fails on S10. The texts said that the checks were capped at 50 repositories.
- The README says that a `LOCKROT_GITHUB_TOKEN` in the step's or job's `env` wins over the
  `github-token` input, and that a Composer credential for github.com wins over both.
- The README FAQ no longer states a size of the PHAR.
- The `ghcr.io/somework/lockrot` image carries brotli-libs 1.2.1-r0 and libcurl 8.23.0-r0, which
  fix CVE-2026-111497 and CVE-2026-92392. The php base image digest is updated as well.

## [1.1.0] - 2026-10-02

Runs lockrot 0.13.0. Read the first two entries if your workflow passes `args` or publishes the
report outside the repository. Inputs and outputs are unchanged. The full list is in the
[0.13.0 release notes](https://github.com/somework/lockrot/releases/tag/v0.13.0).

### Changed

- **Breaking:** a misspelt option or a missing value in `args`, or an invalid `LOCKROT_FAIL_ON` or
  `LOCKROT_TARGET_PHP` in the job's environment, fails the step with exit `2` instead of `1`, so
  `exit-code` no longer reads it as a finding. Action: fix the option or the variable.
- **Breaking:** `format: json` and `format: html` reports carry `run.root_package`, the `name` in
  `composer.json`, even when `extra.lockrot.project` renames the project. Action: if you publish
  the report outside the repository and the name must stay private, remove it first.
- A report quotes no credential and no path of the runner: URLs lose their login and token, and a
  path keeps its last segment. Reports written by earlier versions could carry both.
- With `COMPOSER` set in the job's environment, lockrot reads that manifest and its lock, as
  Composer does.
- An `extra.lockrot` key lockrot does not read gets a warning line in the log, naming the key it
  was probably meant to be.
- `format: html` is the lockrot-report 0.13.0 page.
- `format: json` gains fields that state lockrot's decisions, among them `gate` (whether the run
  fails), `priority_basis` and `origin`; the
  [JSON schemas](https://lockrot.dev/schema/) list them all.

## [1.0.13] - 2026-09-24

### Changed

- Runs lockrot 0.12.0. **The `format: html` page is new.** It is built in its own repository now,
  [somework/lockrot-report](https://github.com/somework/lockrot-report), and lockrot vendors a
  release of it: same report, same keys, same address format, so a link to a filtered view or an
  open package still points where it did. The page carries its own Content-Security-Policy that
  pins its one script and one stylesheet by hash and allows no connection of any kind. On a phone
  the findings come first. A bad escape in the address no longer blanks the page, the theme button
  is right the first time under a dark OS setting, and a release-branch label in the timeline wraps
  instead of being cut short. Nothing else in the run changes: verdicts, priorities, `fail-on`,
  annotations and the PR comment are the same as with 0.11.0. See the
  [0.12.0 release notes](https://github.com/somework/lockrot/releases/tag/v0.12.0).

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

[Unreleased]: https://github.com/somework/lockrot-action/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/somework/lockrot-action/compare/v1.0.13...v1.1.0
[1.0.13]: https://github.com/somework/lockrot-action/compare/v1.0.12...v1.0.13
[1.0.12]: https://github.com/somework/lockrot-action/compare/v1.0.11...v1.0.12
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
