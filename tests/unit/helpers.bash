# Shared setup for the bats suites: a scratch GitHub-like environment and the stub binaries first
# on PATH.
ACTION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

github_env() {
  SCRATCH="$(mktemp -d)"
  export SCRATCH
  export GITHUB_ACTION_PATH="$SCRATCH/action"
  export RUNNER_TEMP="$SCRATCH/temp"
  export GITHUB_WORKSPACE="$SCRATCH/workspace"
  export GITHUB_OUTPUT="$SCRATCH/output"
  export GITHUB_STEP_SUMMARY="$SCRATCH/summary"
  mkdir -p "$GITHUB_ACTION_PATH" "$RUNNER_TEMP" "$GITHUB_WORKSPACE/project"
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"
  cp -R "$ACTION_ROOT/src" "$GITHUB_ACTION_PATH/src"
  printf '{}\n' > "$GITHUB_WORKSPACE/project/composer.json"
  printf '{"packages": []}\n' > "$GITHUB_WORKSPACE/project/composer.lock"
  export PATH="$ACTION_ROOT/tests/unit/stubs:$PATH"
  export CURL_STUB_LOG="$SCRATCH/curl.log"
  export PHP_STUB_LOG="$SCRATCH/php.log"
  export CURL_STUB_ROOT="$SCRATCH/releases"
  cd "$GITHUB_WORKSPACE" || exit 1
}

# A fake release: $1 version, $2 archive content. Returns the sha256.
fake_release() {
  mkdir -p "$CURL_STUB_ROOT/$1"
  printf '%s' "$2" > "$CURL_STUB_ROOT/$1/lockrot.phar"
  local hash
  hash=$(shasum -a 256 "$CURL_STUB_ROOT/$1/lockrot.phar" | cut -c1-64)
  printf '%s  lockrot.phar\n' "$hash" > "$CURL_STUB_ROOT/$1/lockrot.phar.sha256"
  printf '%s\n' "$hash"
}

pin_release() {
  # $1 version, $2 sha256
  printf 'LOCKROT_VERSION=%s\nLOCKROT_SHA256=%s\n' "$1" "$2" > "$GITHUB_ACTION_PATH/lockrot.env"
}

# Outputs are written in the heredoc form (`name<<delimiter`, value, delimiter); the last one wins.
output_value() {
  awk -v name="$1" '
    index($0, name "<<") == 1 { getline; value = $0; found = 1; next }
    END { if (found) print value }
  ' "$GITHUB_OUTPUT"
}

teardown_scratch() {
  [ -n "${SCRATCH:-}" ] && rm -rf "$SCRATCH"
  return 0
}
