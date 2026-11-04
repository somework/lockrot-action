#!/usr/bin/env bats
load helpers

setup() {
  github_env
  export LOCKROT_PHAR="$RUNNER_TEMP/lockrot/lockrot.phar" LOCKROT_VERSION=9.9.9 LOCKROT_CACHE_DIR="$RUNNER_TEMP/lockrot-cache"
  mkdir -p "$RUNNER_TEMP/lockrot" "$LOCKROT_CACHE_DIR"
  printf 'verified archive bytes' > "$LOCKROT_PHAR"
  LOCKROT_SHA256=$(shasum -a 256 "$LOCKROT_PHAR" | cut -c1-64)
  export LOCKROT_SHA256
  export INPUT_WORKING_DIRECTORY=project INPUT_FORMAT=github INPUT_OUTPUT= INPUT_FAIL_ON= INPUT_TARGET_PHP= \
    INPUT_DEV=false INPUT_ALL=false INPUT_STRICT_NETWORK=false INPUT_BASELINE= INPUT_GENERATE_BASELINE=false \
    INPUT_ARGS= INPUT_GITHUB_TOKEN= INPUT_SUMMARY=true
}
teardown() { teardown_scratch; }

run_run() { run bash "$GITHUB_ACTION_PATH/src/run.sh"; }
# The action's scratch directory and the default report directory have random names. They read
# as run/ and step/ here.
random_dirs() { sed -e "s#/lockrot/run\.[A-Za-z0-9]*/#/lockrot/run/#g" -e "s#/lockrot/step\.[A-Za-z0-9]*/#/lockrot/step/#g"; }
main_call() { grep -v -- '--version' "$PHP_STUB_LOG" | grep -v '^-r' | grep -v -- '--format=markdown' | head -n 1 | random_dirs; }
report_value() { output_value report | random_dirs; }

@test "options are passed through and the exit code becomes an output, not a failure" {
  export INPUT_FAIL_ON=silent INPUT_TARGET_PHP=8.4 INPUT_DEV=true INPUT_ALL=yes INPUT_STRICT_NETWORK=1 INPUT_BASELINE=b.json INPUT_ARGS='--foo --bar=1' PHP_STUB_EXIT=1
  run_run
  [ "$status" -eq 0 ]
  [ "$(main_call)" = "$LOCKROT_PHAR lockrot --format=github --fail-on=silent --target-php=8.4 --baseline=b.json --dev --all --strict-network --foo --bar=1 --output=github:$RUNNER_TEMP/lockrot/step/report.txt --output=markdown:$RUNNER_TEMP/lockrot/run/summary.md --markdown-max-bytes=1000000" ]
  [ "$(output_value exit-code)" = "1" ]
  [ "$(report_value)" = "$RUNNER_TEMP/lockrot/step/report.txt" ]
  [[ "$output" == *"running lockrot 9.9.9: --format=github --fail-on=silent"* ]]
}

@test "a comma-separated fail-on list reaches lockrot as one option, unchanged" {
  export INPUT_FAIL_ON=' left-behind,vulnerable-high,unchecked '
  run_run
  [ "$status" -eq 0 ]
  [ "$(main_call)" = "$LOCKROT_PHAR lockrot --format=github --fail-on=left-behind,vulnerable-high,unchecked --output=github:$RUNNER_TEMP/lockrot/step/report.txt --output=markdown:$RUNNER_TEMP/lockrot/run/summary.md --markdown-max-bytes=1000000" ]
}

@test "github annotations are printed with the working directory prepended" {
  run_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning file=project/composer.lock,line=12,title=lockrot%3A silent (critical)::acme/pkg 1.0.0: stub evidence"* ]]
  grep -q '^::warning file=project/composer.lock,' "$(output_value report)"
}

@test "the summary is the same run's markdown report, written through --output, notes as written" {
  export INPUT_FAIL_ON=silent INPUT_TARGET_PHP=8.4
  run_run
  [ "$status" -eq 0 ]
  [ "$(grep -v -- '--version' "$PHP_STUB_LOG" | grep -v '^-r' | wc -l | tr -d ' ')" -eq 1 ]
  ! grep -q -- '--offline' "$PHP_STUB_LOG"
  [ "$(sed -n 1p "$GITHUB_STEP_SUMMARY")" = "### lockrot: stub summary" ]
  grep -q 'offline: repository metadata' "$GITHUB_STEP_SUMMARY"
  grep -q -- '- note: kept' "$GITHUB_STEP_SUMMARY"
  [ -z "$(ls -d "$RUNNER_TEMP"/lockrot/run.* 2> /dev/null)" ]
}

@test "before lockrot 0.13.0 the summary comes from an offline markdown run, minus the offline note" {
  export LOCKROT_VERSION=0.12.0 PHP_STUB_VERSION=0.12.0 INPUT_FAIL_ON=silent INPUT_TARGET_PHP=8.4
  run_run
  [ "$status" -eq 0 ]
  ! grep -q -- '--output=' "$PHP_STUB_LOG"
  grep -q -- "$LOCKROT_PHAR lockrot --format=markdown --offline --fail-on=silent --target-php=8.4" "$PHP_STUB_LOG"
  [ -s "$(output_value report)" ]
  [ "$(sed -n 1p "$GITHUB_STEP_SUMMARY")" = "### lockrot: stub summary" ]
  ! grep -q 'offline: repository metadata' "$GITHUB_STEP_SUMMARY"
  grep -q -- '- note: kept' "$GITHUB_STEP_SUMMARY"
}

@test "with --explain in args no summary is written, since lockrot refuses --output there and a second run would differ" {
  export INPUT_FORMAT=table INPUT_ARGS='--explain=acme/pkg'
  run_run
  [ "$status" -eq 0 ]
  [ "$(main_call)" = "$LOCKROT_PHAR lockrot --format=table --explain=acme/pkg" ]
  ! grep -q -- '--format=markdown' "$PHP_STUB_LOG"
  [ -s "$(output_value report)" ]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
  [ "$(output_value exit-code)" = "0" ]
}

@test "a run that exits 0 without writing the summary file skips the summary and still sets the outputs" {
  # Like LOCKROT_DISABLE=1: lockrot answers --version, then exits 0 before it writes anything.
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; esac; done\nexit 0\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
  [ "$(output_value exit-code)" = "0" ]
  [ "$(report_value)" = "$RUNNER_TEMP/lockrot/step/report.txt" ]
}

@test "a summary file left by an earlier step is not published when this run writes none" {
  printf '### lockrot: stale summary\n' > "$RUNNER_TEMP/lockrot/summary.md"
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; esac; done\nexit 0\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
  [ "$(output_value exit-code)" = "0" ]
}

@test "no summary means no summary file and no markdown cap" {
  export INPUT_SUMMARY=false
  run_run
  [ "$status" -eq 0 ]
  [ "$(main_call)" = "$LOCKROT_PHAR lockrot --format=github --output=github:$RUNNER_TEMP/lockrot/step/report.txt" ]
}

@test "a markdown run feeds the summary directly" {
  export INPUT_FORMAT=markdown
  run_run
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '--format=markdown' "$PHP_STUB_LOG")" -eq 1 ]
  grep -q '### lockrot: stub summary' "$GITHUB_STEP_SUMMARY"
  [ "$(report_value)" = "$RUNNER_TEMP/lockrot/step/report.md" ]
}

@test "the summary is skipped for summary=false, generate-baseline and a failed run" {
  export INPUT_SUMMARY=false
  run_run
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
  export INPUT_SUMMARY=true INPUT_GENERATE_BASELINE=true
  run_run
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
  grep -q -- '--generate-baseline' "$PHP_STUB_LOG"
  export INPUT_GENERATE_BASELINE=false PHP_STUB_EXIT=2
  run_run
  [ "$status" -eq 0 ]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
  [ "$(output_value exit-code)" = "2" ]
  [[ "$output" == *"::warning::lockrot-action: lockrot exited with 2"* ]]
}

@test "a failing summary run is a warning, not a failure" {
  export LOCKROT_VERSION=0.12.0 PHP_STUB_VERSION=0.12.0 PHP_STUB_SUMMARY_EXIT=2
  run_run
  [ "$status" -eq 0 ]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
  [[ "$output" == *"job summary skipped"* ]]
  [ "$(output_value exit-code)" = "0" ]
}

@test "machine formats go to the report file only" {
  export INPUT_FORMAT=sarif INPUT_OUTPUT=build/lockrot.sarif
  run_run
  [ "$status" -eq 0 ]
  [[ "$output" != *"::warning file="* ]]
  [[ "$output" == *"sarif report written to $GITHUB_WORKSPACE/build/lockrot.sarif"* ]]
  [ -s "$GITHUB_WORKSPACE/build/lockrot.sarif" ]
  [ "$(output_value report)" = "$GITHUB_WORKSPACE/build/lockrot.sarif" ]
}

@test "an html page goes to a file named .html and is not printed" {
  export INPUT_FORMAT=html
  run_run
  [ "$status" -eq 0 ]
  [ "$(main_call)" = "$LOCKROT_PHAR lockrot --format=html --output=html:$RUNNER_TEMP/lockrot/step/report.html --output=markdown:$RUNNER_TEMP/lockrot/run/summary.md --markdown-max-bytes=1000000" ]
  [[ "$output" != *"::warning file="* ]]
  [ "$(report_value)" = "$RUNNER_TEMP/lockrot/step/report.html" ]
  [[ "$output" == *"html report written to $(output_value report)"* ]] || false
  [ -s "$(output_value report)" ]
}

@test "an absolute output path is kept" {
  export INPUT_FORMAT=json INPUT_OUTPUT="$SCRATCH/out/report.json"
  run_run
  [ "$status" -eq 0 ]
  [ -s "$SCRATCH/out/report.json" ]
}

@test "the token is exported for lockrot only when given" {
  export INPUT_GITHUB_TOKEN=ghs_stub
  # the stub php records nothing about the environment, so probe through a wrapper
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "${GITHUB_TOKEN:-unset}" "${COMPOSER_CACHE_DIR:-unset}" >> "$SCRATCH/env.log"\nexec "%s/tests/unit/stubs/php" "$@"\n' "$ACTION_ROOT" > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  grep -q "^ghs_stub|$LOCKROT_CACHE_DIR$" "$SCRATCH/env.log"
  unset GITHUB_TOKEN
  export INPUT_GITHUB_TOKEN=
  : > "$SCRATCH/env.log"
  run_run
  grep -q "^unset|$LOCKROT_CACHE_DIR$" "$SCRATCH/env.log"
}

@test "a token in the input goes to lockrot as GITHUB_TOKEN only, so lockrot checks which host issued it" {
  # A GHES runner with a GHES-issued token in the input: lockrot must not treat it as a github.com token.
  export GITHUB_SERVER_URL=https://ghes.example INPUT_GITHUB_TOKEN=ghp_ghes_pat
  unset GITHUB_TOKEN LOCKROT_GITHUB_TOKEN
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "${GITHUB_TOKEN:-unset}" "${LOCKROT_GITHUB_TOKEN:-unset}" >> "$SCRATCH/env.log"\nexec "%s/tests/unit/stubs/php" "$@"\n' "$ACTION_ROOT" > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ "$(tail -n 1 "$SCRATCH/env.log")" = "ghp_ghes_pat|unset" ]
}

@test "a LOCKROT_GITHUB_TOKEN from the job environment reaches lockrot beside the input token" {
  export GITHUB_SERVER_URL=https://ghes.example INPUT_GITHUB_TOKEN=ghs_runner LOCKROT_GITHUB_TOKEN=ghp_dotcom
  unset GITHUB_TOKEN
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "${GITHUB_TOKEN:-unset}" "${LOCKROT_GITHUB_TOKEN:-unset}" >> "$SCRATCH/env.log"\nexec "%s/tests/unit/stubs/php" "$@"\n' "$ACTION_ROOT" > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ "$(tail -n 1 "$SCRATCH/env.log")" = "ghs_runner|ghp_dotcom" ]
}

@test "COMPOSER from the job environment reaches the lockrot process unchanged" {
  export COMPOSER=alt.json
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${COMPOSER:-unset}" >> "$SCRATCH/composer.log"\nexec "%s/tests/unit/stubs/php" "$@"\n' "$ACTION_ROOT" > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ "$(sort -u "$SCRATCH/composer.log")" = "alt.json" ]
}

@test "an archive that changed after verification is refused" {
  printf 'swapped' > "$LOCKROT_PHAR"
  run_run
  [ "$status" -eq 1 ]
  [[ "$output" == *"lockrot.phar changed after it was verified"* ]]
  [ ! -s "$PHP_STUB_LOG" ]
}

@test "args are split on whitespace but never globbed" {
  export INPUT_ARGS='--all *'
  run_run
  [ "$status" -eq 0 ]
  [ "$(main_call)" = "$LOCKROT_PHAR lockrot --format=github --all * --output=github:$RUNNER_TEMP/lockrot/step/report.txt --output=markdown:$RUNNER_TEMP/lockrot/run/summary.md --markdown-max-bytes=1000000" ]
}

@test "a line break in an input is refused before anything runs" {
  export INPUT_OUTPUT="report.txt
exit-code=0"
  run_run
  [ "$status" -eq 1 ]
  [[ "$output" == *"the OUTPUT input must not contain a line break"* ]]
  [ ! -s "$PHP_STUB_LOG" ]
}

@test "before lockrot 0.13.0, a report above the summary limit leaves a note instead" {
  # That lockrot writes the report to stdout only, and only --output files can be capped.
  export INPUT_FORMAT=markdown LOCKROT_VERSION=0.12.0
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 0.12.0"; exit 0;; esac; done\nhead -c 1000001 /dev/zero | tr "\\0" x\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  grep -q 'more than the job summary can hold' "$GITHUB_STEP_SUMMARY"
  [ "$(wc -c < "$GITHUB_STEP_SUMMARY" | tr -d ' ')" -lt 1000 ]
}

@test "an unknown format is refused" {
  export INPUT_FORMAT=xml
  run_run
  [ "$status" -eq 1 ]
  [[ "$output" == *"format 'xml' is not one of"* ]]
  [ -z "$(output_value exit-code)" ]
}

@test "an archive reporting another version is refused" {
  export PHP_STUB_VERSION=0.0.1
  run_run
  [ "$status" -eq 1 ]
  [[ "$output" == *"lockrot.phar reports 'lockrot 0.0.1', expected 'lockrot 9.9.9'"* ]]
}

@test "lockrot is the first argument, so a value after a space stays the value of its option" {
  # Without the command name, Symfony reads the first bare word as the command and exits 1.
  export INPUT_FORMAT=table INPUT_ARGS='--explain acme/pkg'
  run_run
  [ "$status" -eq 0 ]
  [ "$(main_call)" = "$LOCKROT_PHAR lockrot --format=table --explain acme/pkg" ]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
}

@test "the report goes through --output, so a lock named as the output is intact when lockrot reads it" {
  # lockrot refuses composer.lock as an --output target and exits 2; this php stands in for that.
  export INPUT_OUTPUT=project/composer.lock
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; esac; done\nprintf "%%s\\n" "$*" >> "$PHP_STUB_LOG"\ncat "$GITHUB_WORKSPACE/project/composer.lock" > "$SCRATCH/lock-seen"\nexit 2\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  grep -q -- "--output=github:$GITHUB_WORKSPACE/project/composer.lock" "$PHP_STUB_LOG"
  [ "$(cat "$SCRATCH/lock-seen")" = '{"packages": []}' ]
  [ "$(cat "$GITHUB_WORKSPACE/project/composer.lock")" = '{"packages": []}' ]
  [ "$(output_value exit-code)" = "2" ]
}

@test "a report file that lockrot did not write is named in the log, not read" {
  export INPUT_FORMAT=sarif
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; esac; done\nexit 2\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ "$(grep -cF -- 'No such file' <<< "$output")" -eq 0 ]
  grep -qF -- 'lockrot wrote no sarif report' <<< "$output"
  [ "$(output_value exit-code)" = "2" ]
}

@test "a default report path names no file when lockrot wrote none" {
  export INPUT_FORMAT=sarif
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; esac; done\nexit 0\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ "$(report_value)" = "$RUNNER_TEMP/lockrot/step/report.sarif" ]
  [ ! -e "$(output_value report)" ]
}

@test "two steps in one job keep their own default report, so the later one leaves the earlier one alone" {
  # Arrange: two projects, and a lockrot that writes the name of the project it ran in.
  export INPUT_FORMAT=markdown
  mkdir -p "$GITHUB_WORKSPACE/other" "$SCRATCH/bin"
  printf '{}\n' > "$GITHUB_WORKSPACE/other/composer.json"
  printf '{"packages": []}\n' > "$GITHUB_WORKSPACE/other/composer.lock"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; --output=*:*) printf "report of %%s\\n" "${PWD##*/}" > "${a#--output=*:}";; esac; done\nexit 0\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"

  # Act: step a, then step b, each with its own GITHUB_OUTPUT as on a runner.
  export INPUT_WORKING_DIRECTORY=project GITHUB_OUTPUT="$SCRATCH/output-a"
  run_run
  [ "$status" -eq 0 ]
  local report_a
  report_a=$(output_value report)
  export INPUT_WORKING_DIRECTORY=other GITHUB_OUTPUT="$SCRATCH/output-b"
  run_run
  [ "$status" -eq 0 ]
  local report_b
  report_b=$(output_value report)

  # Assert
  [ "$report_a" != "$report_b" ]
  [ "$(cat "$report_a")" = "report of project" ]
  [ "$(cat "$report_b")" = "report of other" ]
}

@test "the github annotation rewrite leaves a file named <output>.tmp beside the report alone" {
  export INPUT_OUTPUT=reports/lockrot.txt
  mkdir -p "$GITHUB_WORKSPACE/reports"
  printf 'user data\n' > "$GITHUB_WORKSPACE/reports/lockrot.txt.tmp"
  run_run
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_WORKSPACE/reports/lockrot.txt.tmp")" = "user data" ]
  grep -q '^::warning file=project/composer.lock,' "$GITHUB_WORKSPACE/reports/lockrot.txt"
}

@test "the github annotation rewrite keeps the file mode that the report was written with" {
  umask 022
  export INPUT_OUTPUT=reports/lockrot.txt
  run_run
  [ "$status" -eq 0 ]
  grep -q '^::warning file=project/composer.lock,' "$GITHUB_WORKSPACE/reports/lockrot.txt"
  [ "$(ls -l "$GITHUB_WORKSPACE/reports/lockrot.txt" | cut -c1-10)" = "-rw-r--r--" ]
}

@test "the github annotation rewrite replaces a read-only report and keeps its mode" {
  # Like lockrot, the stub replaces the report by a rename and carries the earlier mode, 0444 here.
  export INPUT_OUTPUT=reports/lockrot.txt
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; --output=github:*) t=${a#--output=github:}; printf "::warning file=composer.lock,line=3::m\\n" > "$t.new"; chmod 444 "$t.new"; mv -f "$t.new" "$t";; esac; done\nexit 0\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ "$(cat "$GITHUB_WORKSPACE/reports/lockrot.txt")" = "::warning file=project/composer.lock,line=3::m" ]
  [ "$(ls -l "$GITHUB_WORKSPACE/reports/lockrot.txt" | cut -c1-10)" = "-r--r--r--" ]
  [ "$(ls -A "$GITHUB_WORKSPACE/reports")" = "lockrot.txt" ]
}

@test "a github annotation rewrite that cannot write fails the step with an error and keeps the exit-code output" {
  # The stub writes the report, then leaves its directory read-only, so no copy can go beside it.
  export INPUT_OUTPUT=reports/lockrot.txt PHP_STUB_EXIT=1
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; --output=github:*) t=${a#--output=github:}; printf "::warning file=composer.lock,line=3::m\\n" > "$t"; chmod 555 "${t%%/*}";; esac; done\nexit 1\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  chmod 755 "$GITHUB_WORKSPACE/reports"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::lockrot-action: could not rewrite the annotation paths in $GITHUB_WORKSPACE/reports/lockrot.txt"* ]] || false
  [ "$(output_value exit-code)" = "1" ]
  [ "$(cat "$GITHUB_WORKSPACE/reports/lockrot.txt")" = "::warning file=composer.lock,line=3::m" ]
  [ "$(ls -A "$GITHUB_WORKSPACE/reports")" = "lockrot.txt" ]
}

@test "the github annotation rewrite succeeds beside a directory named <output>.tmp" {
  export INPUT_OUTPUT=reports/lockrot.txt
  mkdir -p "$GITHUB_WORKSPACE/reports/lockrot.txt.tmp"
  run_run
  [ "$status" -eq 0 ]
  [ "$(output_value exit-code)" = "0" ]
  [ "$(output_value report)" = "$GITHUB_WORKSPACE/reports/lockrot.txt" ]
  [ -d "$GITHUB_WORKSPACE/reports/lockrot.txt.tmp" ]
  grep -q '^::warning file=project/composer.lock,' "$GITHUB_WORKSPACE/reports/lockrot.txt"
}

@test "a COMPOSER that names a subdirectory manifest from the root keeps lockrot's lock path in the annotations" {
  # The README subdirectory recipe: working-directory stays `.`, and lockrot names the lock
  # apps/api/composer.lock itself, so the action adds no prefix.
  export INPUT_WORKING_DIRECTORY=. COMPOSER=apps/api/composer.json
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; --output=github:*) printf "::warning file=apps/api/composer.lock,line=3::m\\n" > "${a#--output=github:}";; esac; done\nprintf "::warning file=apps/api/composer.lock,line=3::m\\n"\nexit 0\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning file=apps/api/composer.lock,line=3::m"* ]] || false
  [ "$(cat "$(output_value report)")" = "::warning file=apps/api/composer.lock,line=3::m" ]
}

@test "an empty format input runs lockrot with --format=github" {
  export INPUT_FORMAT=
  run_run
  [ "$status" -eq 0 ]
  main_call | grep -q -- '^[^ ]* lockrot --format=github '
}

@test "a format input of whitespace only runs lockrot with --format=github" {
  export INPUT_FORMAT='  '
  run_run
  [ "$status" -eq 0 ]
  main_call | grep -q -- '^[^ ]* lockrot --format=github '
}

@test "the default report directory can be read by other users, as RUNNER_TEMP/lockrot can" {
  run_run
  [ "$status" -eq 0 ]
  [ "$(ls -ld "$(dirname "$(output_value report)")" | cut -c1-10)" = "drwxr-xr-x" ]
}

@test "a default report directory that cannot be made stops the step before lockrot runs" {
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\ncase "$*" in *step.*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v mktemp)" > "$SCRATCH/bin/mktemp"
  chmod +x "$SCRATCH/bin/mktemp"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::lockrot-action: could not make a report directory in $RUNNER_TEMP/lockrot"* ]] || false
  [ -z "$(main_call)" ]
  [ -z "$(output_value report)" ]
}

@test "a default report directory that cannot get mode 755 stops the step with an error" {
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\ncase "$*" in *step.*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v chmod)" > "$SCRATCH/bin/chmod"
  chmod +x "$SCRATCH/bin/chmod"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::lockrot-action: could not make the report directory $RUNNER_TEMP/lockrot/step."*" readable"* ]] || false
  [ -z "$(main_call)" ]
}

@test "generate-baseline writes the report through --output, since stdout stays empty" {
  export INPUT_GENERATE_BASELINE=true
  run_run
  [ "$status" -eq 0 ]
  [ "$(main_call)" = "$LOCKROT_PHAR lockrot --format=github --generate-baseline --output=github:$RUNNER_TEMP/lockrot/step/report.txt" ]
  [ -s "$(output_value report)" ]
}

@test "a markdown run's summary keeps the run's own offline note" {
  export INPUT_FORMAT=markdown
  run_run
  [ "$status" -eq 0 ]
  grep -q 'offline: repository metadata' "$GITHUB_STEP_SUMMARY"
  grep -q -- '- note: kept' "$GITHUB_STEP_SUMMARY"
}

@test "a markdown run that writes no report file skips the summary" {
  export INPUT_FORMAT=markdown
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; esac; done\nexit 0\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
  [ "$(output_value exit-code)" = "0" ]
}

@test "a --markdown-max-bytes in args replaces the cap the action sets for the summary" {
  export INPUT_ARGS='--markdown-max-bytes 65536'
  run_run
  [ "$status" -eq 0 ]
  [ "$(main_call)" = "$LOCKROT_PHAR lockrot --format=github --markdown-max-bytes 65536 --output=github:$RUNNER_TEMP/lockrot/step/report.txt --output=markdown:$RUNNER_TEMP/lockrot/run/summary.md" ]
}

@test "lockrot 0.13 gets no --markdown-max-bytes, which it does not know" {
  export LOCKROT_VERSION=0.13.0 PHP_STUB_VERSION=0.13.0
  run_run
  [ "$status" -eq 0 ]
  [ "$(main_call)" = "$LOCKROT_PHAR lockrot --format=github --output=github:$RUNNER_TEMP/lockrot/step/report.txt --output=markdown:$RUNNER_TEMP/lockrot/run/summary.md" ]
}

@test "a release candidate of lockrot 0.14.0 gets the summary cap" {
  export LOCKROT_VERSION=0.14.0-rc.9 PHP_STUB_VERSION=0.14.0-rc.9
  run_run
  [ "$status" -eq 0 ]
  main_call | grep -q -- ' --markdown-max-bytes=1000000$'
}

@test "a PHP startup warning on stderr does not fail the version check" {
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\necho "PHP Warning:  PHP Startup: Unable to load dynamic library '"'"'missing.so'"'"'" >&2\nexec "%s/tests/unit/stubs/php" "$@"\n' "$ACTION_ROOT" > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ "$(output_value exit-code)" = "0" ]
  [ "$(main_call)" = "$LOCKROT_PHAR lockrot --format=github --output=github:$RUNNER_TEMP/lockrot/step/report.txt --output=markdown:$RUNNER_TEMP/lockrot/run/summary.md --markdown-max-bytes=1000000" ]
}

@test "a version check that fails names what php wrote on stderr" {
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\necho "PHP Parse error: stub" >&2\nexit 255\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 1 ]
  grep -q -- 'does not run on this PHP.*PHP Parse error: stub' <<< "$output"
}

@test "a report at the output path that lockrot did not replace is not published as this run's" {
  # Like LOCKROT_DISABLE=1 with an output file left by an earlier run.
  export INPUT_FORMAT=markdown INPUT_OUTPUT=build/lockrot.md
  mkdir -p "$GITHUB_WORKSPACE/build" "$SCRATCH/bin"
  printf '### OLD REPORT\n' > "$GITHUB_WORKSPACE/build/lockrot.md"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; esac; done\nexit 0\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ ! -s "$GITHUB_STEP_SUMMARY" ]
  grep -qF -- "lockrot wrote no markdown report to $GITHUB_WORKSPACE/build/lockrot.md" <<< "$output"
  [ "$(cat "$GITHUB_WORKSPACE/build/lockrot.md")" = '### OLD REPORT' ]
}

@test "an old sarif file at the output path is not logged as written when lockrot exits 2" {
  export INPUT_FORMAT=sarif INPUT_OUTPUT=build/l.sarif
  mkdir -p "$GITHUB_WORKSPACE/build" "$SCRATCH/bin"
  printf 'old sarif\n' > "$GITHUB_WORKSPACE/build/l.sarif"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; esac; done\nexit 2\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ "$(grep -cF -- 'sarif report written to' <<< "$output")" -eq 0 ]
  grep -qF -- 'lockrot wrote no sarif report' <<< "$output"
}

@test "the annotation rewrite leaves alone an output file that lockrot did not write" {
  export INPUT_OUTPUT=build/annotations.txt
  mkdir -p "$GITHUB_WORKSPACE/build" "$SCRATCH/bin"
  printf '::warning file=composer.lock,line=1::old\n' > "$SCRATCH/real.txt"
  ln -s "$SCRATCH/real.txt" "$GITHUB_WORKSPACE/build/annotations.txt"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; esac; done\nexit 2\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ -L "$GITHUB_WORKSPACE/build/annotations.txt" ]
  [ "$(cat "$SCRATCH/real.txt")" = '::warning file=composer.lock,line=1::old' ]
}

@test "with --explain, a lock named as the output is intact when lockrot reads it and after a failed run" {
  export INPUT_FORMAT=table INPUT_ARGS='--explain=acme/pkg' INPUT_OUTPUT=project/composer.lock
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; esac; done\ncat "$GITHUB_WORKSPACE/project/composer.lock" > "$SCRATCH/lock-seen"\necho "partial"\nexit 2\n' > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ "$(cat "$SCRATCH/lock-seen")" = '{"packages": []}' ]
  [ "$(cat "$GITHUB_WORKSPACE/project/composer.lock")" = '{"packages": []}' ]
}

@test "an output path where an earlier action version kept its summary file keeps the report" {
  export INPUT_FORMAT=sarif INPUT_OUTPUT="$RUNNER_TEMP/lockrot/summary.md"
  run_run
  [ "$status" -eq 0 ]
  [ -s "$RUNNER_TEMP/lockrot/summary.md" ]
  grep -q '### lockrot: stub summary' "$GITHUB_STEP_SUMMARY"
  [ -z "$(ls -d "$RUNNER_TEMP"/lockrot/run.* 2> /dev/null)" ]
}

@test "a PHP startup warning on stdout before the version line does not fail the version check" {
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) printf "Warning: PHP Startup: Unable to load dynamic library\\n"; break;; esac; done\nexec "%s/tests/unit/stubs/php" "$@"\n' "$ACTION_ROOT" > "$SCRATCH/bin/php"
  chmod +x "$SCRATCH/bin/php"
  export PATH="$SCRATCH/bin:$PATH"
  run_run
  [ "$status" -eq 0 ]
  [ "$(output_value exit-code)" = "0" ]
}
