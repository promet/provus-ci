#!/usr/bin/env bash

# Fail loudly and fail on the first broken stage of a pipe. Individual
# commands that are allowed to fail (multidev lookups, "nothing to commit",
# etc.) already guard themselves with `|| true`/manual exit-code checks.
set -o pipefail

on_error() {
  local exit_code=$1 line=$2 command=$3
  echo "=========================================" >&2
  echo "BUILD ERROR" >&2
  echo "  script:  ${BASH_SOURCE[1]:-$0}" >&2
  echo "  line:    $line" >&2
  echo "  command: $command" >&2
  echo "  exit:    $exit_code" >&2
  echo "=========================================" >&2
}
trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

path=$(dirname "$0")
source $path/.env

# Normalize build metadata across CI providers so the platform scripts below
# don't need to know whether they're running under GitHub Actions or Travis CI.
export BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-$TRAVIS_BUILD_NUMBER}}"
export COMMIT_SHA="${COMMIT_SHA:-${GITHUB_SHA:-$TRAVIS_COMMIT}}"

source $path/$HOSTING/deploy.sh
