#!/usr/bin/env bash
# Step 2 of the action: run the verified PHAR against the project, keep the report, print it the
# way the format wants (workflow commands for `github`), write the job summary and expose the exit
# code as an output. Whatever lockrot's exit code, this script exits 0 once it has handled lockrot's
# output, and the action's last step turns that code into the step result after the cache is saved.
# It exits non-zero when a command fails, before lockrot runs or after it, for example when the
# annotation rewrite, the report move or an output write fails. The cache save and the last step
# then do not run.
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
  format=$(trim "${INPUT_FORMAT:-}")
  [ -n "$format" ] || format=github
  case "$format" in
    table|json|github|sarif|gitlab|markdown|html) ;;
    *) fail "format '${format}' is not one of table, json, github, sarif, gitlab, markdown, html" ;;
  esac
  local temp_dir
  temp_dir="$(native_path "${RUNNER_TEMP:?RUNNER_TEMP is not set}")/lockrot"
  mkdir -p "$temp_dir"
  # A directory of this run's own, so no output path can name a file the action writes or deletes.
  SCRATCH_DIR=$(mktemp -d "${temp_dir}/run.XXXXXX")
  trap 'rm -rf "$SCRATCH_DIR"' EXIT

  # The last line of stdout only: a php.ini that loads a missing extension writes a startup
  # warning on every run, to stderr and with display_startup_errors also to stdout, and lockrot
  # still runs.
  local reported
  if ! reported=$(php "$phar" --version 2> "$SCRATCH_DIR/version.err"); then
    fail "the downloaded lockrot.phar does not run on this PHP ($(php -r 'echo PHP_VERSION;' 2>/dev/null || echo unknown)): ${reported} $(tr '\n' ' ' < "$SCRATCH_DIR/version.err")"
  fi
  reported=$(printf '%s\n' "$reported" | tail -n 1)
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
  ! has_option --format ${extra[@]+"${extra[@]}"} \
    || fail "args sets --format, which replaces the format the action prints, names and rewrites the report by. Set the format input instead"
  ! has_working_dir ${extra[@]+"${extra[@]}"} \
    || fail "args sets the working directory (-d or --working-dir), which moves the project away from the files the action checks and annotates. Set the working-directory input instead"

  local explain=false
  ! has_option --explain ${extra[@]+"${extra[@]}"} || explain=true

  local report
  if [ -n "$(trim "${INPUT_OUTPUT:-}")" ]; then
    report=$(native_path "$(trim "$INPUT_OUTPUT")")
    case "$report" in
      /*|[A-Za-z]:/*) ;;
      *) report="$(native_path "${GITHUB_WORKSPACE:-$PWD}")/${report}" ;;
    esac
    refuse_project_file "$report" "$work_dir" ${extra[@]+"${extra[@]}"}
    # lockrot can exit before it writes, and an if: always() upload of the path must then find no
    # file rather than an earlier run's report.
    if [ -e "$report" ] || [ -L "$report" ]; then
      rm -f -- "$report" || fail "could not remove the earlier report at ${report}"
    fi
  else
    # A directory of this step's own: a later step of the job must not replace this report. Mode
    # 755 as for RUNNER_TEMP/lockrot, so a later step that runs as another user can read it.
    local step_dir
    step_dir=$(mktemp -d "${temp_dir}/step.XXXXXX") || fail "could not make a report directory in ${temp_dir}"
    chmod 755 "$step_dir" || fail "could not make the report directory ${step_dir} readable"
    report="${step_dir}/report.$(report_extension "$format")"
  fi
  mkdir -p "$(dirname "$report")"
  # From lockrot 0.13.0 a format the log prints goes through --output, and so does a run whose stdout
  # holds no report. lockrot's own check of the target is then the second line of defence, after
  # refuse_project_file. Otherwise a document format is not printed, so its stdout is the report,
  # and lockrot renders it once. --explain refuses --output, and an older lockrot has none, so
  # these get stdout moved there after a run that exits 0 or 1.
  local stdout_file report_by_output=false stdout_report=true
  stdout_file="${SCRATCH_DIR}/stdout.$(report_extension "$format")"
  if [ "$generate_baseline" = true ] || ! prints_report ${extra[@]+"${extra[@]}"}; then
    stdout_report=false
  fi
  if [ "$explain" = false ] && version_at_least "$version" 0.13.0; then
    case "$stdout_report:$format" in
      false:*|true:github|true:table|true:markdown)
        report_by_output=true
        args+=("--output=${format}:${report}")
        ;;
    esac
  fi
  # A report taken from stdout must hold no PHP message, such as the startup warning of a php.ini
  # that loads a missing extension. PHP writes those to stderr instead, which the log shows too.
  local -a php_flags=()
  [ "$report_by_output" = true ] || php_flags=(-d display_errors=stderr -d display_startup_errors=0)

  # The job summary shows the markdown format. A markdown run's own report is that. From lockrot
  # 0.13.0 another format's run writes it beside the report with --output, so both come from one
  # analysis; an older lockrot gets it from a second, offline run after this one. --explain refuses
  # --output, and a second run would show a whole offline report, whose advisories and gate line
  # need not match the step, so it gets none.
  local summary_wanted=false summary_file="" summary_temp=""
  if is_true "${INPUT_SUMMARY:-true}" && [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ "$generate_baseline" = false ]; then
    if [ "$explain" = true ]; then
      case "$format" in
        table) log "job summary skipped: with --explain, the explanation is in the step log and the report file" ;;
        *) log "job summary skipped: with --explain, the explanation is in the report file" ;;
      esac
    else
      summary_wanted=true
    fi
  fi
  if [ "$summary_wanted" = true ]; then
    if [ "$format" = markdown ]; then
      summary_file=$report
    elif version_at_least "$version" 0.13.0; then
      summary_temp="${SCRATCH_DIR}/summary.md"
      summary_file=$summary_temp
      args+=("--output=markdown:${summary_temp}")
    fi
    # lockrot then leaves rows out of a large markdown file instead of the runner refusing it.
    if version_at_least "$version" 0.14.0 && ! has_option --markdown-max-bytes ${extra[@]+"${extra[@]}"}; then
      args+=("--markdown-max-bytes=${SUMMARY_LIMIT_BYTES}")
    fi
  fi

  export COMPOSER_CACHE_DIR="${LOCKROT_CACHE_DIR:?LOCKROT_CACHE_DIR is not set}"
  export COMPOSER_NO_INTERACTION=1
  # Never LOCKROT_GITHUB_TOKEN: the action cannot tell which host issued the token, and lockrot
  # sends that variable to github.com unchecked. lockrot checks GITHUB_TOKEN against the runner's host.
  if [ -n "$(trim "${INPUT_GITHUB_TOKEN:-}")" ]; then
    export GITHUB_TOKEN="$INPUT_GITHUB_TOKEN"
  fi
  ! version_at_least "$version" 0.14.0 || withheld_token_notice

  log "running lockrot ${version}: ${args[*]}"
  # The command name first: Symfony reads the first bare word before it as a command name, so an
  # option value after a space would run another command, or none, with exit 1.
  local code=0
  (cd -- "$work_dir" && php ${php_flags[@]+"${php_flags[@]}"} "$phar" lockrot "${args[@]}") > "$stdout_file" || code=$?
  # Set before the rewrite, the move and the summary, so a later job step that reads them gets
  # lockrot's code when one of these fails.
  set_output exit-code "$code"
  set_output report "$report"

  [ "$format" != github ] || rewrite_annotation_paths "$stdout_file" "$work_dir" || fail "could not rewrite the annotation paths in ${stdout_file}"
  # A stdout that holds no report, such as the text of --help or --version, goes to the log under
  # every format.
  case "$stdout_report:$format" in
    false:*|true:github|true:table|true:markdown) cat "$stdout_file" ;;
  esac
  # lockrot can exit before it writes anything: LOCKROT_DISABLE, --help, a usage error.
  local report_written=false
  if [ "$report_by_output" = true ]; then
    if [ -f "$report" ]; then
      report_written=true
      [ "$format" != github ] || rewrite_annotation_paths "$report" "$work_dir" || fail "could not rewrite the annotation paths in ${report}"
    fi
  # A document or an explanation is never empty, so empty stdout means lockrot exited before it, as
  # under LOCKROT_DISABLE. A lockrot older than 0.13.0 keeps the empty file of v1.1.0.
  elif [ "$code" -le 1 ] && { [ -s "$stdout_file" ] \
    || { [ "$explain" = false ] && ! version_at_least "$version" 0.13.0; }; }; then
    mv -f -- "$stdout_file" "$report" || fail "could not write the report to ${report}"
    report_written=true
  fi
  if [ "$report_written" = false ]; then
    log "lockrot wrote no ${format} report to ${report}"
  else
    case "$format" in
      github|table|markdown) ;;
      *) log "${format} report written to ${report} ($(wc -c < "$report" | tr -d ' ') bytes)" ;;
    esac
  fi
  if [ "$code" -gt 2 ]; then
    warn "lockrot exited with ${code}, which is no lockrot exit code: PHP stopped it, for example on a fatal error such as an exhausted memory_limit, or the process was killed. The step fails as a setup failure"
  elif [ "$code" -gt 1 ]; then
    warn "lockrot exited with ${code}; see the log above for the reason"
  fi

  if [ "$summary_wanted" = true ] && [ "$code" -le 1 ]; then
    if [ -z "$summary_file" ]; then
      write_summary "$phar" "$work_dir" "$SCRATCH_DIR"
    elif { [ "$summary_file" = "$report" ] && [ "$report_written" = true ]; } \
      || { [ "$summary_file" = "$summary_temp" ] && [ -f "$summary_file" ]; }; then
      append_summary "$summary_file" keep-notes
      # withheld_token_notice prints to the log only, and a reader looks at the job summary.
      [ -z "$WITHHELD_TOKEN_TEXT" ] || printf '\n> lockrot-action: %s.\n' "$WITHHELD_TOKEN_TEXT" >> "$GITHUB_STEP_SUMMARY" \
        || error "could not append the token notice to the job summary ${GITHUB_STEP_SUMMARY}"
    else
      log "job summary skipped: lockrot exited with ${code} and wrote no summary"
    fi
  fi
}

# From lockrot 0.14.0, lockrot withholds GITHUB_TOKEN from github.com when GITHUB_SERVER_URL or
# GH_HOST names another host or reads as two hosts. It says so in its anonymous-cap note, which
# appears only when it skips a package, and otherwise only with -v. So this notice names the
# variable that works there on every such run, and main() repeats it in the job summary when it
# writes one. It names the variable, not its value: a URL can carry userinfo.
WITHHELD_TOKEN_TEXT=""
withheld_token_notice() {
  [ -n "${GITHUB_TOKEN:-}" ] && [ -z "${LOCKROT_GITHUB_TOKEN:-}" ] || return 0
  local name value scheme bare authority reason token="GITHUB_TOKEN from the step's or job's env"
  [ -z "$(trim "${INPUT_GITHUB_TOKEN:-}")" ] || token="GITHUB_TOKEN, and so the github-token input,"
  for name in GITHUB_SERVER_URL GH_HOST; do
    value=${!name:-}
    [ -n "$value" ] || continue
    # lockrot first reads the value without userinfo: its scheme, if one starts with a letter, and
    # the text after the last `@`. It also reads the host of the whole value's authority, which ends
    # at the first `/`, `?` or `#`.
    scheme=
    [[ ! "$value" =~ ^[A-Za-z][A-Za-z0-9+.-]*:// ]] || scheme=${BASH_REMATCH[0]}
    bare=$value
    [[ "${value#"$scheme"}" != *@* ]] || bare="${scheme}${value##*@}"
    authority=$(without_scheme "$value")
    authority=${authority%%[/?#]*}
    if [ "$(url_host "$bare")" != github.com ]; then
      reason="${name} names another host"
    elif [ "$(url_host "$authority" "$value")" != github.com ] || [[ "$authority" == *\\* ]]; then
      reason="URL parsers read ${name} two ways"
    else
      continue
    fi
    WITHHELD_TOKEN_TEXT="lockrot does not send ${token} to github.com, because ${reason}. Unless Composer holds a github.com credential, set LOCKROT_GITHUB_TOKEN to a github.com token in the step's or job's env to check repository activity on github.com"
    notice "$WITHHELD_TOKEN_TEXT"
    return 0
  done
}

# The host of URL or bare host $1 in lower case: the text after the scheme and after the last `@`,
# up to a path, a query, a fragment or a backslash. lockrot also cuts at the last `@`, because
# userinfo can hold any character. An empty port is no port, as for PHP's parse_url. Other ports
# stay only when $2 (default $1), the text that lockrot gives to parse_url for this reading, is an
# http(s) URL or holds no `://`: lockrot then reads it as https://$2. An ssh:// or git:// port
# belongs to the transport, not to the host that lockrot sends tokens to.
url_host() {
  local rest
  rest=$(without_scheme "$1")
  rest=${rest##*@}
  rest=${rest%%[/?#\\]*}
  rest=${rest%:}
  if [[ "${2:-$1}" == *://* ]] && ! [[ "${2:-$1}" =~ ^[Hh][Tt][Tt][Pp][Ss]?:// ]] \
    && [[ "$rest" == *:* ]] && php_port "${rest##*:}"; then
    rest=${rest%:*}
  fi
  printf '%s\n' "$rest" | tr '[:upper:]' '[:lower:]'
}

# Whether $1 is a port that PHP's parse_url accepts: at most 5 characters, which strtol reads as a
# number from 0 to 65535. Any other port makes parse_url fail, and lockrot then withholds the token.
php_port() {
  [ "${#1}" -le 5 ] && [[ "$1" =~ ^[[:space:]]*([+-]?)([0-9]+) ]] || return 1
  local value=$((10#${BASH_REMATCH[2]}))
  [ "${BASH_REMATCH[1]}" != - ] || [ "$value" -eq 0 ] || return 1
  [ "$value" -le 65535 ]
}

# $1 without a leading scheme and `://`, as PHP's parse_url reads a scheme. A `://` after text that
# is no scheme stays, so the value reads as a bare host, as lockrot reads it.
without_scheme() {
  if [[ "$1" =~ ^[A-Za-z0-9+.-]+:// ]]; then
    printf '%s\n' "${1#*://}"
  else
    printf '%s\n' "$1"
  fi
}

# Fails when report path $1 names a file that lockrot reads or that the baseline is, or has a file
# name that Windows reads as another, as lockrot refuses for --output: a report taken from stdout
# has no other check.
# $2 is the working directory, and the rest are the args words. Composer reads COMPOSER relative to
# the working directory, and every baseline is relative to the manifest's directory.
refuse_project_file() {
  local report=$1 project manifest lock base candidate name file key i
  project=$(cd -P -- "$2" 2> /dev/null && pwd -P) \
    || fail "could not enter the working directory $2, so the output check cannot tell whether output names a project file"
  shift 2
  manifest=$(native_path "$(trim "${COMPOSER:-}")")
  [ -n "$manifest" ] || manifest=composer.json
  lock=$(composer_lock_name)
  case "$manifest" in /*|[A-Za-z]:/*) ;; *) manifest="${project}/${manifest}" ;; esac
  case "$lock" in /*|[A-Za-z]:/*) ;; *) lock="${project}/${lock}" ;; esac
  base=$(dirname "$manifest")
  local configured
  # The output file is removed once this check passes, so a baseline it cannot name must stop the step.
  configured=$(configured_baseline "$manifest") \
    || fail "could not read extra.lockrot.baseline from ${manifest} (php exited with ${configured}), so the output check cannot tell whether output names the baseline"
  local -a baselines=("$(trim "${INPUT_BASELINE:-}")" "$configured")
  while IFS= read -r file; do
    baselines+=("$file")
  done < <(option_values --baseline "$@")
  # Each protected path is resolved once: every resolution forks, and forks are slow under Git Bash.
  local -a protected=() keys=() reasons=()
  for file in "${project}/composer.json" "${project}/composer.lock" "$manifest" "$lock"; do
    protected+=("$file")
    keys+=("$(path_key "$file")")
    reasons+=("which is ${file}, a file that lockrot reads")
  done
  for file in "${baselines[@]}"; do
    [ -n "$file" ] || continue
    file=$(native_path "$file")
    case "$file" in /*|[A-Za-z]:/*) ;; *) file="${base}/${file}" ;; esac
    protected+=("$file")
    keys+=("$(path_key "$file")")
    reasons+=("which is the baseline file ${file}")
  done
  case "${report##*/}" in
    # The input is trimmed, so the name cannot end in a space, the third name that lockrot refuses.
    *:*|*.) fail "the output input names ${report}, a file name that ends in a dot or holds a colon, which Windows reads as another file. The action writes no report there" ;;
  esac
  while IFS= read -r candidate; do
    name=$(basename "$candidate" | tr '[:upper:]' '[:lower:]')
    case "$name" in
      composer.json|composer.lock) fail "the output input names ${report}, a ${name} that lockrot reads. The action writes no report there" ;;
    esac
    key=$(path_key "$candidate")
    i=0
    while [ "$i" -lt "${#protected[@]}" ]; do
      if [ "$candidate" -ef "${protected[i]}" ] || [ "$key" = "${keys[i]}" ]; then
        fail "the output input names ${report}, ${reasons[i]}. The action writes no report there"
      fi
      i=$((i + 1))
    done
  done < <(link_chain "$report")
}

# extra.lockrot.baseline from manifest $1, else lockrot-baseline.json. The value carries a marker,
# so a PHP startup line on stdout is never read as the value. When PHP fails, prints its exit code
# and returns 1.
configured_baseline() {
  local value="" code=0
  if [ -f "$1" ]; then
    # shellcheck disable=SC2016 # PHP code, expanded by PHP
    value=$(php -d display_startup_errors=0 -d display_errors=stderr -r '$j = json_decode((string) file_get_contents($argv[1]), true); $b = $j["extra"]["lockrot"]["baseline"] ?? null; if (is_string($b)) { echo "lockrot-baseline=", $b, "\n"; }' -- "$1" 2> /dev/null) || code=$?
    if [ "$code" -ne 0 ]; then
      printf '%s\n' "$code"
      return 1
    fi
    value=$(printf '%s\n' "$value" | sed -n 's/^lockrot-baseline=//p' | head -n 1)
  fi
  printf '%s\n' "${value:-lockrot-baseline.json}"
}

# The values of option $1 in the words after it, joined by `=` or after a space, one per line.
option_values() {
  local name=$1 argument take=false
  shift
  for argument in "$@"; do
    if [ "$take" = true ]; then
      printf '%s\n' "$argument"
      take=false
      continue
    fi
    case "$argument" in
      "$name") take=true ;;
      "$name"=*) printf '%s\n' "${argument#"$name"=}" ;;
    esac
  done
}

# $1, then each file its symlinks point at, one per line: a write to $1 lands on the last one.
LINK_HOPS=40
link_chain() {
  local path=$1 target hops=0
  printf '%s\n' "$path"
  while [ -L "$path" ] && [ "$hops" -lt "$LINK_HOPS" ]; do
    target=$(native_path "$(readlink "$path")") || return 0
    case "$target" in /*|[A-Za-z]:/*) path=$target ;; *) path="$(dirname "$path")/${target}" ;; esac
    printf '%s\n' "$path"
    hops=$((hops + 1))
  done
}

# The resolved spelling of path $1 in lower case. Two paths with one key name one file, unless the
# filesystem tells letter case apart. A missing file in another case is one file on macOS and
# Windows, and refusing it on Linux too costs only a rename of the report.
path_key() {
  resolved_path "$1" | tr '[:upper:]' '[:lower:]'
}

# Absolute path $1 the way the system reads it once `mkdir -p` makes its missing directories: the
# nearest existing directory resolved physically, and `.` and `..` folded in the part below it. A
# fold can reach an existing directory again, so this repeats until nothing changes.
resolved_path() {
  local path=$1 next i
  for i in 1 2 3 4 5 6 7 8; do
    next=$(resolve_once "$path")
    [ "$next" != "$path" ] || break
    path=$next
  done
  printf '%s\n' "$path"
}

resolve_once() {
  local dir=$1 resolved segment
  local -a tail=() folded=()
  until resolved=$(cd -P "$dir" 2> /dev/null && pwd -P); do
    tail=("$(basename "$dir")" ${tail[@]+"${tail[@]}"})
    dir=$(dirname "$dir")
  done
  resolved=${resolved%/}
  for segment in ${tail[@]+"${tail[@]}"}; do
    case "$segment" in
      .|'') ;;
      ..)
        if [ "${#folded[@]}" -gt 0 ]; then
          unset 'folded[${#folded[@]}-1]'
          folded=(${folded[@]+"${folded[@]}"})
        else
          resolved=$(dirname "${resolved:-/}")
          resolved=${resolved%/}
        fi
        ;;
      *) folded+=("$segment") ;;
    esac
  done
  printf '%s' "$resolved"
  for segment in ${folded[@]+"${folded[@]}"}; do printf '/%s' "$segment"; done
  [ -n "$resolved" ] || [ "${#folded[@]}" -gt 0 ] || printf '/'
  printf '\n'
}

# Whether the args words give lockrot's working-directory option: `-d dir`, `-ddir`,
# `--working-dir dir` or `--working-dir=dir`.
has_working_dir() {
  local argument
  for argument in "$@"; do
    case "$argument" in -d*|--working-dir|--working-dir=*) return 0 ;; esac
  done
  return 1
}

# Whether lockrot prints the report to stdout with the args words: --generate-baseline, a quiet
# option, --help and --version keep it off stdout, and a short option bundle can hold -q, -h or -V.
prints_report() {
  local argument
  for argument in "$@"; do
    case "$argument" in
      --generate-baseline|--generate-baseline=*|--quiet|--silent|--help|--version) return 1 ;;
      --*) ;;
      -*[qhV]*) return 1 ;;
    esac
  done
  return 0
}

# Whether the arguments after $1 give option $1, with its value joined by `=` or after a space.
has_option() {
  local name=$1 argument
  shift
  for argument in "$@"; do
    case "$argument" in "$name"|"$name"=*) return 0 ;; esac
  done
  return 1
}

# The runner refuses a step summary above 1 MiB. lockrot 0.14.0 and newer keep the summary file
# within this size (--markdown-max-bytes); from an older lockrot, a larger report is left to the
# log and the report file. A summary rendered by a second, offline run carries an offline note
# that is an artefact of that run, not of the one it shows, so it is dropped; `keep-notes` is for a
# summary the main run wrote itself, whose notes are all its own. A summary file that takes no
# append gives an error but does not fail the step, which keeps lockrot's exit code and the cache.
SUMMARY_LIMIT_BYTES=1000000
append_summary() {
  local size failed="could not append the job summary to ${GITHUB_STEP_SUMMARY}"
  size=$(wc -c < "$1" | tr -d ' ')
  if [ "$size" -gt "$SUMMARY_LIMIT_BYTES" ]; then
    printf '### lockrot\n\nThe report is %s bytes, more than the job summary can hold; see the step log or the report file.\n' "$size" >> "$GITHUB_STEP_SUMMARY" || error "$failed"
    return 0
  fi
  if [ "${2:-}" = keep-notes ]; then
    cat "$1" >> "$GITHUB_STEP_SUMMARY" || error "$failed"
    return 0
  fi
  # grep exits 1 when it keeps no line, so only the redirection of the group can fail it.
  { grep -v -F -x -e "- note: offline: repository metadata served from Composer's cache" "$1" || true; } \
    >> "$GITHUB_STEP_SUMMARY" || error "$failed"
}

# The markdown format is the one shaped for a page, so it is what the job summary shows. When the
# main run used another format and could not write it too (lockrot before 0.13.0),
# the report is produced again from the caches the first run just filled — `--offline`, so no
# request is repeated and no rate-limit budget is spent twice.
write_summary() {
  local phar=$1 work_dir=$2 temp_dir=$3
  build_args
  local -a args=(--format=markdown --offline ${COMMON_ARGS[@]+"${COMMON_ARGS[@]}"})
  local summary code=0
  summary="${temp_dir}/summary.md"
  (cd -- "$work_dir" && php "$phar" lockrot "${args[@]}") > "$summary" 2> "$summary.err" || code=$?
  if [ "$code" -le 1 ]; then
    append_summary "$summary"
  else
    warn "job summary skipped: the offline summary run exited with ${code}: $(tr '\n' ' ' < "$summary.err")"
  fi
  rm -f "$summary" "$summary.err"
}

main "$@"
