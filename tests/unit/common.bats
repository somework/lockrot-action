#!/usr/bin/env bats
load helpers

setup() {
  # shellcheck source=src/common.sh
  . "$ACTION_ROOT/src/common.sh"
  SCRATCH="$(mktemp -d)"
}
teardown() { teardown_scratch; }

@test "normalize_version strips the v prefix and whitespace" {
  [ "$(normalize_version ' v0.2.1 ')" = "0.2.1" ]
  [ "$(normalize_version '0.10.0')" = "0.10.0" ]
  [ "$(normalize_version '1.0.0-rc.1')" = "1.0.0-rc.1" ]
}

@test "normalize_version refuses anything that is not a release version" {
  run normalize_version latest
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::"*"not a lockrot release version"* ]]
  run normalize_version 0.2
  [ "$status" -eq 1 ]
  run normalize_version '0.2.1; rm -rf /'
  [ "$status" -eq 1 ]
  run normalize_version ''
  [ "$status" -eq 1 ]
}

@test "normalize_sha256 accepts bare, prefixed, sha256sum and uppercase forms" {
  local hex=fc71049fa5bb1bf36e3b9301abc813a8c8642cf5768db06d4928faea3fdf65b0
  [ "$(normalize_sha256 "$hex")" = "$hex" ]
  [ "$(normalize_sha256 "sha256:$hex")" = "$hex" ]
  [ "$(normalize_sha256 "$hex  lockrot.phar")" = "$hex" ]
  [ "$(normalize_sha256 "$(printf '%s' "$hex" | tr a-f A-F)")" = "$hex" ]
  run normalize_sha256 "not a hash"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not contain a sha256 hash"* ]]
}

@test "read_env_value reads a key without sourcing the file" {
  printf '# comment\nLOCKROT_VERSION=0.2.1\nLOCKROT_SHA256=abc\nEVIL=$(touch %s/pwned)\n' "$SCRATCH" > "$SCRATCH/lockrot.env"
  [ "$(read_env_value "$SCRATCH/lockrot.env" LOCKROT_VERSION)" = "0.2.1" ]
  [ "$(read_env_value "$SCRATCH/lockrot.env" EVIL)" = "\$(touch $SCRATCH/pwned)" ]
  [ ! -e "$SCRATCH/pwned" ]
  run read_env_value "$SCRATCH/lockrot.env" MISSING
  [ "$status" -eq 1 ]
}

@test "is_true accepts the usual spellings only" {
  is_true true; is_true TRUE; is_true 1; is_true yes; is_true on
  ! is_true false; ! is_true 0; ! is_true ''; ! is_true maybe
}

@test "native_path turns backslashes into slashes" {
  [ "$(native_path 'D:\a\_temp')" = "D:/a/_temp" ]
  [ "$(native_path '/tmp/x')" = "/tmp/x" ]
}

@test "trim strips surrounding whitespace" {
  [ "$(trim '  a b  ')" = "a b" ]
  [ "$(trim '')" = "" ]
}

@test "rewrite_annotation_paths prefixes the working directory and leaves other lines alone" {
  printf '::error file=composer.lock,line=8,title=t::m\nplain line file=composer.lock,\n::notice::note\n' > "$SCRATCH/r"
  rewrite_annotation_paths "$SCRATCH/r" "./apps/web/"
  [ "$(sed -n 1p "$SCRATCH/r")" = "::error file=apps/web/composer.lock,line=8,title=t::m" ]
  [ "$(sed -n 2p "$SCRATCH/r")" = "plain line file=composer.lock," ]
  [ "$(sed -n 3p "$SCRATCH/r")" = "::notice::note" ]
}

@test "rewrite_annotation_paths is a no-op for the workspace root" {
  printf '::error file=composer.lock,line=8::m\n' > "$SCRATCH/r"
  rewrite_annotation_paths "$SCRATCH/r" "."
  [ "$(cat "$SCRATCH/r")" = "::error file=composer.lock,line=8::m" ]
  rewrite_annotation_paths "$SCRATCH/r" "./"
  [ "$(cat "$SCRATCH/r")" = "::error file=composer.lock,line=8::m" ]
}

@test "rewrite_annotation_paths copes with sed-special characters in the directory" {
  printf '::warning file=composer.lock,line=1::m\n' > "$SCRATCH/r"
  rewrite_annotation_paths "$SCRATCH/r" 'a&b/c'
  [ "$(cat "$SCRATCH/r")" = "::warning file=a&b/c/composer.lock,line=1::m" ]
}

@test "set_output uses the heredoc form so a value cannot smuggle a second output" {
  export GITHUB_OUTPUT="$SCRATCH/out"
  : > "$GITHUB_OUTPUT"
  set_output report "a=b
exit-code=0"
  set_output exit-code 1
  [ "$(grep -c '^exit-code<<' "$GITHUB_OUTPUT")" -eq 1 ]
  [ "$(grep -c '^report<<' "$GITHUB_OUTPUT")" -eq 1 ]
  ! grep -q '^exit-code=0' "$GITHUB_OUTPUT"
  delimiter=$(sed -n 's/^exit-code<<//p' "$GITHUB_OUTPUT")
  [ "$(sed -n "/^exit-code<<$delimiter\$/{n;p;}" "$GITHUB_OUTPUT")" = "1" ]
}

@test "reject_line_breaks refuses an input with a newline or a carriage return" {
  export INPUT_A='fine' INPUT_B="two
lines"
  reject_line_breaks INPUT_A
  run reject_line_breaks INPUT_A INPUT_B
  [ "$status" -eq 1 ]
  [[ "$output" == *"the B input must not contain a line break"* ]]
  export INPUT_C="$(printf 'cr\rhere')"
  run reject_line_breaks INPUT_C
  [ "$status" -eq 1 ]
}

@test "reject_absolute_path refuses absolute and drive-letter paths" {
  reject_absolute_path working-directory apps/api
  reject_absolute_path working-directory ./apps
  run reject_absolute_path working-directory /tmp/x
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be relative to the workspace"* ]]
  run reject_absolute_path working-directory 'D:/a/x'
  [ "$status" -eq 1 ]
}

@test "report_extension maps formats to file extensions" {
  [ "$(report_extension json)" = json ]
  [ "$(report_extension gitlab)" = json ]
  [ "$(report_extension sarif)" = sarif ]
  [ "$(report_extension markdown)" = md ]
  [ "$(report_extension html)" = html ]
  [ "$(report_extension github)" = txt ]
  [ "$(report_extension table)" = txt ]
}

@test "resolve_latest_version reads the version out of the redirect" {
  export PATH="$ACTION_ROOT/tests/unit/stubs:$PATH"
  export CURL_STUB_REDIRECT="https://github.com/somework/lockrot/releases/download/v0.3.0/lockrot.phar"
  [ "$(resolve_latest_version)" = "0.3.0" ]
  export CURL_STUB_REDIRECT="https://github.com/somework/lockrot/releases"
  run resolve_latest_version
  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected redirect"* ]]
  export CURL_STUB_REDIRECT_EXIT=22
  run resolve_latest_version
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not resolve the latest lockrot release"* ]]
}
