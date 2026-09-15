#!/usr/bin/env bats
load helpers

setup() {
  github_env
  PINNED_SHA=$(fake_release 0.2.1 'pinned archive bytes')
  pin_release 0.2.1 "$PINNED_SHA"
  export INPUT_WORKING_DIRECTORY=project INPUT_VERSION= INPUT_CHECKSUM= INPUT_PHP_VERSION=
}
teardown() { teardown_scratch; }

run_setup() { run bash "$GITHUB_ACTION_PATH/src/setup.sh"; }

@test "default run downloads the pinned release and verifies the pinned sha256" {
  run_setup
  [ "$status" -eq 0 ]
  [[ "$output" == *"lockrot 0.2.1 downloaded and verified (sha256 $PINNED_SHA)"* ]]
  [ "$(output_value version)" = "0.2.1" ]
  [ "$(output_value phar)" = "$RUNNER_TEMP/lockrot/lockrot.phar" ]
  [ "$(cat "$RUNNER_TEMP/lockrot/lockrot.phar")" = "pinned archive bytes" ]
  [ "$(output_value cache-dir)" = "$RUNNER_TEMP/lockrot/cache" ]
  [ -d "$RUNNER_TEMP/lockrot/cache" ]
  [ "$(output_value php-needed)" = "false" ]
  lock_hash=$(output_value lock-hash)
  [ "${#lock_hash}" -eq 16 ]
  [[ "$(output_value cache-date)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
  # only the archive was fetched: the pinned hash made the .sha256 download unnecessary
  [ "$(wc -l < "$CURL_STUB_LOG" | tr -d ' ')" -eq 1 ]
  grep -q '/releases/download/v0.2.1/lockrot.phar$' "$CURL_STUB_LOG"
}

@test "a tampered archive is refused and removed" {
  pin_release 0.2.1 0000000000000000000000000000000000000000000000000000000000000000
  run_setup
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::lockrot-action: sha256 mismatch for lockrot 0.2.1"* ]]
  [[ "$output" == *"nothing will run"* ]]
  [ ! -e "$RUNNER_TEMP/lockrot/lockrot.phar" ]
}

@test "an explicit version is verified against the release's own .sha256 file" {
  fake_release 0.2.0 'older archive' > /dev/null
  export INPUT_VERSION=v0.2.0
  run_setup
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "0.2.0" ]
  [ "$(cat "$RUNNER_TEMP/lockrot/lockrot.phar")" = "older archive" ]
  grep -q '/releases/download/v0.2.0/lockrot.phar.sha256$' "$CURL_STUB_LOG"
}

@test "an explicit version whose published hash does not match is refused" {
  fake_release 0.2.0 'older archive' > /dev/null
  printf 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff  lockrot.phar\n' > "$CURL_STUB_ROOT/0.2.0/lockrot.phar.sha256"
  export INPUT_VERSION=0.2.0
  run_setup
  [ "$status" -eq 1 ]
  [[ "$output" == *"sha256 mismatch for lockrot 0.2.0"* ]]
}

@test "latest resolves through the release redirect" {
  fake_release 9.9.9 'newest archive' > /dev/null
  export INPUT_VERSION=latest CURL_STUB_REDIRECT="https://github.com/somework/lockrot/releases/download/v9.9.9/lockrot.phar"
  run_setup
  [ "$status" -eq 0 ]
  [ "$(output_value version)" = "9.9.9" ]
  [ "$(cat "$RUNNER_TEMP/lockrot/lockrot.phar")" = "newest archive" ]
}

@test "the checksum input wins over the pinned hash" {
  export INPUT_CHECKSUM="sha256:$(printf '%s' 'pinned archive bytes' | shasum -a 256 | cut -c1-64)"
  run_setup
  [ "$status" -eq 0 ]
  pin_release 0.2.1 0000000000000000000000000000000000000000000000000000000000000000
  run_setup
  [ "$status" -eq 0 ]
  export INPUT_CHECKSUM=1111111111111111111111111111111111111111111111111111111111111111
  run_setup
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected 1111111111111111111111111111111111111111111111111111111111111111"* ]]
}

@test "a version that is not a release is refused before anything is downloaded" {
  export INPUT_VERSION=main
  run_setup
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a lockrot release version"* ]]
  [ ! -s "$CURL_STUB_LOG" ]
}

@test "a missing composer.lock is reported with the working directory" {
  export INPUT_WORKING_DIRECTORY=elsewhere
  run_setup
  [ "$status" -eq 1 ]
  [[ "$output" == *"no composer.lock in 'elsewhere' (working-directory)"* ]]
}

@test "a missing download is reported" {
  export INPUT_VERSION=0.0.1
  run_setup
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not download https://github.com/somework/lockrot/releases/download/v0.0.1/lockrot.phar"* ]]
}

@test "php-needed is true when php-version is requested or the runner's PHP is too old" {
  export INPUT_PHP_VERSION=8.3
  run_setup
  [ "$status" -eq 0 ]
  [ "$(output_value php-needed)" = "true" ]
  export INPUT_PHP_VERSION= PHP_STUB_TOO_OLD=1
  run_setup
  [ "$status" -eq 0 ]
  [ "$(output_value php-needed)" = "true" ]
  [[ "$output" == *"no PHP 7.4+ on this runner"* ]]
}

@test "Windows-style paths are normalised" {
  export RUNNER_TEMP="${RUNNER_TEMP//\//\\}"
  run_setup
  [ "$status" -eq 0 ]
  [[ "$(output_value phar)" != *"\\"* ]]
}
