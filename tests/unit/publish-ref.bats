#!/usr/bin/env bats

# A clone whose origin has the default branch main, a commit on main tagged v1.2.0, and a branch
# `side` with one commit off main, tagged v1.2.1.
setup() {
  SCRATCH="$(mktemp -d)"
  export SCRATCH DEFAULT_BRANCH=main
  SCRIPT="$BATS_TEST_DIRNAME/../../.github/scripts/publish-ref.sh"
  local origin="$SCRATCH/origin"
  git init -q -b main "$origin"
  git -C "$origin" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m one
  git -C "$origin" tag v1.2.0
  git -C "$origin" checkout -q -b side
  git -C "$origin" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m two
  git -C "$origin" tag v1.2.1
  git -C "$origin" tag v1.2.1-rc.1
  git -C "$origin" checkout -q main
  git clone -q "$origin" "$SCRATCH/clone"
  cd "$SCRATCH/clone" || exit 1
}
teardown() { rm -rf "$SCRATCH"; }

@test "the default branch may publish" {
  run "$SCRIPT" refs/heads/main
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a vMAJOR.MINOR.PATCH tag whose commit is on the default branch may publish" {
  git checkout -q v1.2.0
  run "$SCRIPT" refs/tags/v1.2.0
  [ "$status" -eq 0 ]
}

@test "a release tag whose commit is not on the default branch may not publish" {
  git checkout -q v1.2.1
  run "$SCRIPT" refs/tags/v1.2.1
  [ "$status" -eq 1 ]
  [ "$output" = "the commit of refs/tags/v1.2.1 is not on main" ]
}

@test "a tag that is no vMAJOR.MINOR.PATCH may not publish" {
  git checkout -q v1.2.1-rc.1
  run "$SCRIPT" refs/tags/v1.2.1-rc.1
  [ "$status" -eq 1 ]
  [ "$output" = "refs/tags/v1.2.1-rc.1 is neither main nor a vMAJOR.MINOR.PATCH tag" ]
}

@test "another branch may not publish, also when its commit is on the default branch" {
  run "$SCRIPT" refs/heads/side
  [ "$status" -eq 1 ]
  [ "$output" = "refs/heads/side is neither main nor a vMAJOR.MINOR.PATCH tag" ]
  run "$SCRIPT" refs/heads/main-copy
  [ "$status" -eq 1 ]
}

@test "a clone without the default branch may not publish" {
  git checkout -q v1.2.0
  git update-ref -d refs/remotes/origin/main
  run "$SCRIPT" refs/tags/v1.2.0
  [ "$status" -eq 1 ]
  [ "$output" = "the commit of refs/tags/v1.2.0 is not on main" ]
}
