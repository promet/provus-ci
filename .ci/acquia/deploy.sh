#!/bin/bash

CURRENT_BRANCH=`git name-rev --name-only HEAD`
CURRENT_TAG=`git name-rev --tags --name-only $(git rev-parse HEAD)`

composer install

remove_nests_git() {
  find docroot/ vendor/ -type d -name ".git" -prune -exec rm -rf {} +
}

add_remote() {
  git remote add deploy $REMOTE_GIT_REPO
}

quiet_git() {
  stdout=$(tempfile)
  stderr=$(tempfile)

  if ! git "$@" </dev/null >$stdout 2>$stderr; then
    cat $stderr >&2
    rm -f $stdout $stderr
    exit 1
  fi

  rm -f $stdout $stderr
}

set_perms() {
  chmod u+x vendor/drush/drush/drush
  mkdir -p docroot/sites/default/files
  chmod u+x docroot/sites/default/files
}

pantheon_conn_switch() {
  $TERMINUS_BIN connection:set ${PANTHEON_SITE_NAME}.dev $1
}

build() {
  echo ""
  #some custom script here if you build theme using node etc
}

setup() {
  echo "SETUP"
  remove_nests_git
  add_remote
  # uncomment calling build If you have customer build function
  #build
  set_perms
}

push() {
  local add_build="${1}-build" # Append -build to the branch name
  echo "PUSH"
  git remote -v
  quiet_git add --force docroot vendor hooks scripts drush config patches private  composer.*
  quiet_git commit -m "Build for $add_build"
  git push deploy HEAD:refs/heads/$add_build --force
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
