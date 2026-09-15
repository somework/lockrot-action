#!/usr/bin/env bash
# Shared helpers for setup.sh and run.sh. Sourced, never executed. Must stay bash 3.2 compatible
# (macOS ships 3.2 as /bin/bash) and must work under Git Bash on Windows runners.

LOCKROT_REPO="somework/lockrot"
LOCKROT_RELEASES="https://github.com/${LOCKROT_REPO}/releases"

# Workflow commands: a `::error::` line is what turns a script failure into a red annotation.
# Written to stderr so the message survives when the failing function runs inside `$(...)`,
# whose stdout is captured and discarded by the failing assignment.
fail() {
  printf '::error::lockrot-action: %s\n' "$*" >&2
  exit 1
}
warn() { printf '::warning::lockrot-action: %s\n' "$*"; }
notice() { printf '::notice::lockrot-action: %s\n' "$*"; }
log() { printf 'lockrot-action: %s\n' "$*"; }

set_output() {
  # $1 name, $2 single-line value
  if [ -z "${GITHUB_OUTPUT:-}" ]; then
    log "output $1=$2"
    return 0
  fi
  printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
}

# Backslashes become slashes: Git Bash on Windows accepts `D:/a/_temp` everywhere, and so do
# php.exe and the Node-based actions the path is handed to. Everything else passes through.
native_path() { printf '%s\n' "${1//\\//}"; }

# Strips leading/trailing whitespace.
trim() {
  local value=$1
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s\n' "$value"
}

# true/1/yes/on, case-insensitively.
is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

sha256_of() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | cut -c1-64
  elif command -v shasum > /dev/null 2>&1; then
    shasum -a 256 "$1" | cut -c1-64
  else
    fail "neither sha256sum nor shasum is available to verify the download"
  fi
}

# Reads KEY=value from a file without sourcing it.
read_env_value() {
  # $1 file, $2 key
  local line
  line=$(grep -E "^${2}=" "$1" | head -n 1) || true
  [ -n "$line" ] || fail "$2 not found in $1"
  printf '%s\n' "${line#*=}"
}

# `v0.2.1` or `0.2.1` -> `0.2.1`; anything that is not a release version is refused.
normalize_version() {
  local version
  version=$(trim "$1")
  version=${version#v}
  case "$version" in
    *[!0-9A-Za-z.+-]*|'') fail "'$1' is not a lockrot release version (expected e.g. 0.2.1)" ;;
  esac
  if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'; then
    fail "'$1' is not a lockrot release version (expected e.g. 0.2.1)"
  fi
  printf '%s\n' "$version"
}

# 64 hex characters, lowercased, from a bare hash or `sha256:<hex>` or `sha256sum` output.
normalize_sha256() {
  local hex
  hex=$(printf '%s' "$1" | grep -Eo '[0-9A-Fa-f]{64}' | head -n 1 | tr '[:upper:]' '[:lower:]') || true
  [ -n "$hex" ] || fail "'$1' does not contain a sha256 hash"
  printf '%s\n' "$hex"
}

# The version `releases/latest` currently points at, read from the redirect GitHub answers with
# for the latest-asset URL. No API call, no token, no JSON parsing.
resolve_latest_version() {
  local redirect
  redirect=$(curl -fsS --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 30 \
    -o /dev/null -w '%{redirect_url}' "${LOCKROT_RELEASES}/latest/download/lockrot.phar") \
    || fail "could not resolve the latest lockrot release from ${LOCKROT_RELEASES}/latest"
  case "$redirect" in
    */releases/download/v*/lockrot.phar) ;;
    *) fail "unexpected redirect for the latest lockrot release: '$redirect'" ;;
  esac
  redirect=${redirect%/lockrot.phar}
  printf '%s\n' "${redirect##*/download/v}"
}

download() {
  # $1 url, $2 destination
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 120 -o "$2" "$1" \
    || fail "could not download $1"
}

# `file=composer.lock` in a workflow command names the file relative to the checkout root, so a
# project in a subdirectory needs the directory prepended for the annotation to land on its lock.
rewrite_annotation_paths() {
  # $1 report file, $2 working directory relative to the workspace
  local dir=$2 escaped
  dir=${dir#./}
  dir=${dir%/}
  [ -n "$dir" ] && [ "$dir" != "." ] || return 0
  escaped=$(printf '%s' "$dir" | sed -e 's/[\/&]/\\&/g')
  sed -e "s/^\(::[a-z]* file=\)composer\.lock,/\1${escaped}\/composer.lock,/" "$1" > "$1.tmp" \
    && mv "$1.tmp" "$1"
}

report_extension() {
  case "$1" in
    json|gitlab) printf 'json\n' ;;
    sarif) printf 'sarif\n' ;;
    markdown) printf 'md\n' ;;
    *) printf 'txt\n' ;;
  esac
}
