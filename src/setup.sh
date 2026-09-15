#!/usr/bin/env bash
# Step 1 of the action: pick the lockrot release, download lockrot.phar, verify its sha256, decide
# whether PHP has to be installed, and hand the paths and cache key parts to the next steps.
set -euo pipefail
# shellcheck source=src/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

php_is_usable() {
  command -v php > /dev/null 2>&1 || return 1
  php -r 'exit(PHP_VERSION_ID >= 70400 ? 0 : 1);' > /dev/null 2>&1
}

main() {
  reject_line_breaks INPUT_VERSION INPUT_CHECKSUM INPUT_WORKING_DIRECTORY INPUT_PHP_VERSION INPUT_CACHE

  local action_path work_dir pinned_version pinned_sha requested version expected
  action_path=$(native_path "${GITHUB_ACTION_PATH:?GITHUB_ACTION_PATH is not set}")
  work_dir=$(native_path "$(trim "${INPUT_WORKING_DIRECTORY:-.}")")
  [ -n "$work_dir" ] || work_dir=.
  reject_absolute_path working-directory "$work_dir"
  [ -f "$work_dir/composer.lock" ] || fail "no composer.lock in '$work_dir' (working-directory)"

  pinned_version=$(read_env_value "$action_path/lockrot.env" LOCKROT_VERSION)
  pinned_sha=$(read_env_value "$action_path/lockrot.env" LOCKROT_SHA256)

  requested=$(trim "${INPUT_VERSION:-}")
  expected=
  if [ -z "$requested" ]; then
    version=$pinned_version
  elif [ "$requested" = "latest" ]; then
    version=$(normalize_version "$(resolve_latest_version)")
  else
    version=$(normalize_version "$requested")
  fi
  if [ -n "$(trim "${INPUT_CHECKSUM:-}")" ]; then
    expected=$(normalize_sha256 "$INPUT_CHECKSUM")
  elif [ "$version" = "$pinned_version" ]; then
    expected=$pinned_sha
  fi

  local temp dir base phar actual
  temp=$(native_path "${RUNNER_TEMP:?RUNNER_TEMP is not set}")
  dir="$temp/lockrot"
  # The cache is restored by a separate action into a directory of its own, beside the archive's
  # directory rather than inside it, so nothing a cache archive contains can sit next to the
  # verified file.
  mkdir -p "$dir" "$temp/lockrot-cache"
  base="${LOCKROT_RELEASES}/download/v${version}"
  phar="$dir/lockrot.phar"
  rm -f "$phar"
  download "$base/lockrot.phar" "$phar"
  if [ -z "$expected" ]; then
    download "$base/lockrot.phar.sha256" "$dir/lockrot.phar.sha256"
    expected=$(normalize_sha256 "$(cat "$dir/lockrot.phar.sha256")")
  fi
  actual=$(sha256_of "$phar")
  if [ "$actual" != "$expected" ]; then
    rm -f "$phar"
    fail "sha256 mismatch for lockrot ${version}: expected ${expected}, downloaded ${actual}; nothing will run"
  fi
  log "lockrot ${version} downloaded and verified (sha256 ${actual})"

  local php_needed=false
  if [ -n "$(trim "${INPUT_PHP_VERSION:-}")" ]; then
    php_needed=true
  elif ! php_is_usable; then
    php_needed=true
    log "no PHP 7.4+ on this runner; installing one with shivammathur/setup-php"
  fi

  local cache_enabled=false
  if is_true "${INPUT_CACHE:-true}"; then
    cache_enabled=true
  fi

  set_output phar "$phar"
  set_output sha256 "$actual"
  set_output version "$version"
  set_output php-needed "$php_needed"
  set_output cache-enabled "$cache_enabled"
  set_output cache-dir "$temp/lockrot-cache"
  set_output lock-hash "$(sha256_of "$work_dir/composer.lock" | cut -c1-16)"
  set_output cache-date "$(date -u +%Y-%m-%d)"
}

main "$@"
