#!/bin/bash

CURRENT_BRANCH=`git name-rev --name-only HEAD`
CURRENT_TAG=`git name-rev --tags --name-only $(git rev-parse HEAD)`

require_env() {
  local missing=()
  for var in "$@"; do
    [ -z "${!var}" ] && missing+=("$var")
  done
  if [ "${#missing[@]}" -ne 0 ]; then
    echo "=========================================" >&2
    echo "...Missing required environment variable(s): ${missing[*]}" >&2
    echo "...Check your .ci/.env and CI provider secrets." >&2
    echo "=========================================" >&2
    exit 1
  fi
}

require_env REMOTE_GIT_REPO

remove_nests_git() {
  find docroot/ vendor/ -type d -name ".git" -prune -exec rm -rf {} +
}

add_remote() {
  git remote add deploy $REMOTE_GIT_REPO 2>/dev/null || git remote set-url deploy $REMOTE_GIT_REPO
}

quiet_git() {
  stdout=$(mktemp)
  stderr=$(mktemp)

  if ! git "$@" </dev/null >"$stdout" 2>"$stderr"; then
    echo "...git $* failed:" >&2
    cat "$stderr" >&2
    rm -f "$stdout" "$stderr"
    exit 1
  fi

  rm -f "$stdout" "$stderr"
}

set_perms() {
  chmod u+x vendor/drush/drush/drush
  mkdir -p docroot/sites/default/files
  chmod u+x docroot/sites/default/files
}

git_init() {
  git config --local user.email "ci-bot@provus-ci"
  git config --local user.name "provus-ci"
}

build() {
  echo ""
  #some custom script here if you build theme using node etc
}

setup() {
  echo "SETUP"
  composer install --no-interaction --prefer-dist --optimize-autoloader || exit 1
  remove_nests_git
  add_remote
  git_init
  # uncomment calling build If you have customer build function
  #build
  set_perms
}

push() {
  local add_build="${1}-build"
  echo "PUSH"
  git remote -v

  # safer add loop
  for path in docroot vendor hooks scripts drush config patches private composer.*; do
    [ -e "$path" ] && git add --force "$path"
  done

  quiet_git commit -m "Build for $add_build" || echo "No changes to commit."
  quiet_git push deploy HEAD:refs/heads/$add_build --force
}

tag() {
  echo "Deploy tag $CURRENT_TAG"
  quiet_git tag -d $CURRENT_TAG
  quiet_git add --force docroot vendor hooks scripts drush config patches private  composer.*
  quiet_git commit -m "Pushing tag to $HOSTING..."
  quiet_git tag $CURRENT_TAG
  quiet_git push deploy $CURRENT_TAG --force
}

## ==============
## main() below.
## ==============


if [[ "$CURRENT_BRANCH" == release-* || "$CURRENT_BRANCH" == develop || "$CURRENT_BRANCH" == hotfix-* || "$CURRENT_BRANCH" == feature-* ]]; then
  setup
  push "$CURRENT_BRANCH"
elif [[ "$CURRENT_TAG" != "undefined" ]]; then
  setup
  tag
fi
