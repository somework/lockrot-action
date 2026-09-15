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
main_call() { grep -v -- '--version' "$PHP_STUB_LOG" | grep -v '^-r' | grep -v -- '--format=markdown' | head -n 1; }

@test "options are passed through and the exit code becomes an output, not a failure" {
  export INPUT_FAIL_ON=silent INPUT_TARGET_PHP=8.4 INPUT_DEV=true INPUT_ALL=yes INPUT_STRICT_NETWORK=1 INPUT_BASELINE=b.json INPUT_ARGS='--foo --bar=1' PHP_STUB_EXIT=1
  run_run
  [ "$status" -eq 0 ]
  [ "$(main_call)" = "$LOCKROT_PHAR --format=github --fail-on=silent --target-php=8.4 --baseline=b.json --dev --all --strict-network --foo --bar=1" ]
  [ "$(output_value exit-code)" = "1" ]
  [ "$(output_value report)" = "$RUNNER_TEMP/lockrot/report.txt" ]
  [[ "$output" == *"running lockrot 9.9.9: --format=github --fail-on=silent"* ]]
}

@test "github annotations are printed with the working directory prepended" {
  run_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning file=project/composer.lock,line=12,title=lockrot%3A silent (critical)::acme/pkg 1.0.0: stub evidence"* ]]
  grep -q '^::warning file=project/composer.lock,' "$RUNNER_TEMP/lockrot/report.txt"
}

@test "the summary is rendered from an offline markdown run with the same options, minus the offline note" {
  export INPUT_FAIL_ON=silent INPUT_TARGET_PHP=8.4
  run_run
  [ "$status" -eq 0 ]
  grep -q -- '--format=markdown --offline --fail-on=silent --target-php=8.4' "$PHP_STUB_LOG"
  [ "$(sed -n 1p "$GITHUB_STEP_SUMMARY")" = "### lockrot: stub summary" ]
  ! grep -q 'offline: repository metadata' "$GITHUB_STEP_SUMMARY"
  grep -q -- '- note: kept' "$GITHUB_STEP_SUMMARY"
}

@test "a markdown run feeds the summary directly" {
  export INPUT_FORMAT=markdown
  run_run
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '--format=markdown' "$PHP_STUB_LOG")" -eq 1 ]
  grep -q '### lockrot: stub summary' "$GITHUB_STEP_SUMMARY"
  [ "$(output_value report)" = "$RUNNER_TEMP/lockrot/report.md" ]
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
  export PHP_STUB_SUMMARY_EXIT=2
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
  [ "$(main_call)" = "$LOCKROT_PHAR --format=github --all *" ]
}

@test "a line break in an input is refused before anything runs" {
  export INPUT_OUTPUT="report.txt
exit-code=0"
  run_run
  [ "$status" -eq 1 ]
  [[ "$output" == *"the OUTPUT input must not contain a line break"* ]]
  [ ! -s "$PHP_STUB_LOG" ]
}

@test "a report above the summary limit leaves a note instead" {
  export INPUT_FORMAT=markdown
  mkdir -p "$SCRATCH/bin"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case $a in --version) echo "lockrot 9.9.9"; exit 0;; esac; done\nhead -c 1000001 /dev/zero | tr "\\0" x\n' > "$SCRATCH/bin/php"
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
}

@test "an archive reporting another version is refused" {
  export PHP_STUB_VERSION=0.0.1
  run_run
  [ "$status" -eq 1 ]
  [[ "$output" == *"lockrot.phar reports 'lockrot 0.0.1', expected 'lockrot 9.9.9'"* ]]
}
