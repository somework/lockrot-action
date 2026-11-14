#!/usr/bin/env bash
# Whether a workflow run for git ref $1 may publish: move the major tag, push or sign the image.
# It may for the branch that DEFAULT_BRANCH names, and for a vMAJOR.MINOR.PATCH tag whose commit,
# checked out as HEAD, is on origin/DEFAULT_BRANCH. The clone needs the history of both.
# Exit 0: it may. Exit 1: it may not, and stdout holds the reason.
# A write-access dispatch or release must not publish code that the default branch's review never saw.
set -u
ref=${1:?usage: publish-ref.sh <git ref>}
branch=${DEFAULT_BRANCH:-}
if [ -z "$branch" ]; then
  echo "DEFAULT_BRANCH is not set"
  exit 1
fi

[ "$ref" != "refs/heads/${branch}" ] || exit 0
if [[ ! "$ref" =~ ^refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "${ref} is neither ${branch} nor a vMAJOR.MINOR.PATCH tag"
  exit 1
fi
if ! git merge-base --is-ancestor HEAD "refs/remotes/origin/${branch}" 2> /dev/null; then
  echo "the commit of ${ref} is not on ${branch}"
  exit 1
fi
