#!/usr/bin/env bash
# Step 2 of the action: run the verified PHAR against the project, keep the report, print it the
# way the format wants (workflow commands for `github`), write the job summary and expose the exit
# code as an output. This script itself exits 0; the action's last step turns lockrot's exit code
# into the step result, after the cache has been saved.
set -euo pipefail
# shellcheck source=src/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Fills COMMON_ARGS with the options shared by the main run and the summary run.
COMMON_ARGS=()
build_args() {
  local fail_on target_php baseline
  fail_on=$(trim "${INPUT_FAIL_ON:-}")
  target_php=$(trim "${INPUT_TARGET_PHP:-}")
  baseline=$(trim "${INPUT_BASELINE:-}")
  COMMON_ARGS=()
  [ -z "$fail_on" ] || COMMON_ARGS+=("--fail-on=${fail_on}")
  [ -z "$target_php" ] || COMMON_ARGS+=("--target-php=${target_php}")
  [ -z "$baseline" ] || COMMON_ARGS+=("--baseline=${baseline}")
  ! is_true "${INPUT_DEV:-false}" || COMMON_ARGS+=(--dev)
  ! is_true "${INPUT_ALL:-false}" || COMMON_ARGS+=(--all)
  ! is_true "${INPUT_STRICT_NETWORK:-false}" || COMMON_ARGS+=(--strict-network)
}

main() {
  reject_line_breaks INPUT_WORKING_DIRECTORY INPUT_FORMAT INPUT_OUTPUT INPUT_FAIL_ON INPUT_TARGET_PHP \
    INPUT_BASELINE INPUT_ARGS INPUT_GITHUB_TOKEN

  local phar version expected actual work_dir format
  phar=${LOCKROT_PHAR:?LOCKROT_PHAR is not set}
  version=${LOCKROT_VERSION:?LOCKROT_VERSION is not set}
  expected=${LOCKROT_SHA256:?LOCKROT_SHA256 is not set}
  # Verified again right before it runs: two other actions ran between the download and this
  # step, and the check costs a few milliseconds.
  actual=$(sha256_of "$phar")
  [ "$actual" = "$expected" ] || fail "lockrot.phar changed after it was verified (sha256 ${actual}, verified ${expected}); nothing will run"
  work_dir=$(native_path "$(trim "${INPUT_WORKING_DIRECTORY:-.}")")
  [ -n "$work_dir" ] || work_dir=.
  format=$(trim "${INPUT_FORMAT:-github}")
  case "$format" in
    table|json|github|sarif|gitlab|markdown|html) ;;
    *) fail "format '${format}' is not one of table, json, github, sarif, gitlab, markdown, html" ;;
  esac

  local reported
  if ! reported=$(php "$phar" --version 2>&1); then
    fail "the downloaded lockrot.phar does not run on this PHP ($(php -r 'echo PHP_VERSION;' 2>/dev/null || echo unknown)): ${reported}"
  fi
  [ "$reported" = "lockrot ${version}" ] || fail "lockrot.phar reports '${reported}', expected 'lockrot ${version}'"

  build_args
  local -a args=("--format=${format}" ${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"})
  local generate_baseline=false
  if is_true "${INPUT_GENERATE_BASELINE:-false}"; then
    generate_baseline=true
    args+=(--generate-baseline)
  fi
  local -a extra=()
  if [ -n "$(trim "${INPUT_ARGS:-}")" ]; then
    # Word-split on whitespace only: quoting is not interpreted, and `set -f` keeps a `*` from
    # turning into file names.
    set -f
    # shellcheck disable=SC2206
    extra=(${INPUT_ARGS})
    set +f
    args+=("${extra[@]}")
  fi

  # The job summary shows the markdown format. From lockrot 0.13.0 the run writes it beside the
  # main report with --output, so both come from one analysis; an older lockrot, or a run with
  # --explain (which refuses --output), gets it from a second, offline run after this one.
  local summary_wanted=false summary_file="" summary_inline=false
  if is_true "${INPUT_SUMMARY:-true}" && [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ "$generate_baseline" = false ]; then
    summary_wanted=true
    if [ "$format" != markdown ] && version_at_least "$version" 0.13.0 && ! has_explain ${extra[@]+"${extra[@]}"}; then
      summary_file="$(native_path "${RUNNER_TEMP:?RUNNER_TEMP is not set}")/lockrot/summary.md"
      mkdir -p "$(dirname "$summary_file")"
      args+=("--output=markdown:${summary_file}")
      summary_inline=true
    fi
  fi

  local report
  if [ -n "$(trim "${INPUT_OUTPUT:-}")" ]; then
    report=$(native_path "$(trim "$INPUT_OUTPUT")")
    case "$report" in
      /*|[A-Za-z]:/*) ;;
      *) report="$(native_path "${GITHUB_WORKSPACE:-$PWD}")/${report}" ;;
    esac
  else
    report="$(native_path "${RUNNER_TEMP:?RUNNER_TEMP is not set}")/lockrot/report.$(report_extension "$format")"
  fi
  mkdir -p "$(dirname "$report")"

  export COMPOSER_CACHE_DIR="${LOCKROT_CACHE_DIR:?LOCKROT_CACHE_DIR is not set}"
  export COMPOSER_NO_INTERACTION=1
  if [ -n "$(trim "${INPUT_GITHUB_TOKEN:-}")" ]; then
    export GITHUB_TOKEN="$INPUT_GITHUB_TOKEN"
  fi

  log "running lockrot ${version}: ${args[*]}"
  local code=0
  (cd "$work_dir" && php "$phar" "${args[@]}") > "$report" || code=$?

  case "$format" in
    github)
      rewrite_annotation_paths "$report" "$work_dir"
      cat "$report"
      ;;
    table|markdown)
      cat "$report"
      ;;
    *)
      log "${format} report written to ${report} ($(wc -c < "$report" | tr -d ' ') bytes)"
      ;;
  esac
  if [ "$code" -gt 1 ]; then
    warn "lockrot exited with ${code}; see the log above for the reason"
  fi

  if [ "$summary_wanted" = true ] && [ "$code" -le 1 ]; then
    if [ "$summary_inline" = true ]; then
      append_summary "$summary_file" keep-notes
    else
      write_summary "$phar" "$work_dir" "$format" "$report"
    fi
  fi
  [ -z "$summary_file" ] || rm -f "$summary_file"

  set_output exit-code "$code"
  set_output report "$report"
}

# Whether the extra arguments ask for --explain, with or without a value.
has_explain() {
  local argument
  for argument in "$@"; do
    case "$argument" in --explain|--explain=*) return 0 ;; esac
  done
  return 1
}

# The runner refuses a step summary above 1 MiB; a report that large is left to the log and the
# report file. A summary rendered by a second, offline run carries an offline note that is an
# artefact of that run, not of the one it shows, so it is dropped; `keep-notes` is for a summary
# the main run wrote itself, whose notes are all its own.
SUMMARY_LIMIT_BYTES=1000000
append_summary() {
  local size
  size=$(wc -c < "$1" | tr -d ' ')
  if [ "$size" -gt "$SUMMARY_LIMIT_BYTES" ]; then
    printf '### lockrot\n\nThe report is %s bytes, more than the job summary can hold; see the step log or the report file.\n' "$size" >> "$GITHUB_STEP_SUMMARY"
    return 0
  fi
  if [ "${2:-}" = keep-notes ]; then
    cat "$1" >> "$GITHUB_STEP_SUMMARY"
    return 0
  fi
  grep -v -F -x -e "- note: offline: repository metadata served from Composer's cache" "$1" \
    >> "$GITHUB_STEP_SUMMARY" || true
}

# The markdown format is the one shaped for a page, so it is what the job summary shows. When the
# main run used another format and could not write it too (lockrot before 0.13.0, or --explain),
# the report is produced again from the caches the first run just filled — `--offline`, so no
# request is repeated and no rate-limit budget is spent twice.
write_summary() {
  local phar=$1 work_dir=$2 format=$3 report=$4
  if [ "$format" = "markdown" ]; then
    append_summary "$report"
    return 0
  fi
  build_args
  local -a args=(--format=markdown --offline ${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"})
  local summary code=0
  summary="$(native_path "${RUNNER_TEMP:?RUNNER_TEMP is not set}")/lockrot/summary.md"
  (cd "$work_dir" && php "$phar" "${args[@]}") > "$summary" 2> "$summary.err" || code=$?
  if [ "$code" -le 1 ]; then
    append_summary "$summary"
  else
    warn "job summary skipped: the offline summary run exited with ${code}: $(tr '\n' ' ' < "$summary.err")"
  fi
  rm -f "$summary" "$summary.err"
}

main "$@"
