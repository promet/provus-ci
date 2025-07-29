#!/bin/bash

CURRENT_BRANCH=$(git name-rev --name-only HEAD)
CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null | sed 's/\^0//g' || echo "undefined")

composer install

SITE_ROOT=$(pwd)
ACQUIA_SUBFOLDER=$(echo "$SITE_ROOT"/../TMP_ACQUIA)

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

remove_acquia_files(){
    rm -rf $ACQUIA_SUBFOLDER/vendor
    rm -rf $ACQUIA_SUBFOLDER/web
}

#this part can be changed depending on what needs to be cleared before pushing to repo

cleanup(){
    echo "Cleaning up"
    rm -rf $SITE_ROOT/tests $SITE_ROOT/BEHAT/ $SITE_ROOT/.git*
    find docroot/ vendor/ -type d -name ".git" -prune -exec rm -rf {} +
    #rm -f $SITE_ROOT/docroot/sites/default/settings.local.php
}

#sync files from github to ACQUIA folder

rsync_files(){
  echo "Rsync of files on going"
  echo "---------------------------------------"
  rsync -a --stats $SITE_ROOT/  $ACQUIA_SUBFOLDER/
  echo "---------------------------------------"
}

push() {
  git fetch --all
  local add_build="${1}-build"
  echo "PUSH"

  if git ls-remote --heads origin "$add_build" | grep -q "$add_build"; then
    echo "Branch $add_build exists remotely. Checking it out..."
    git checkout "$add_build"
  else
    echo "Branch $add_build does not exist. Creating it..."
    git checkout -b "$add_build"
  fi

  remove_acquia_files
  rsync_files

  quiet_git add --force docroot vendor hooks scripts drush config patches private .travis composer.*
  git commit -q -m "Build for $add_build"
  echo "pushing to acquia"
  git push origin $add_build --force
}

tag() {
  git fetch --all
  echo "Checking if tag exist"

 if git rev-parse "$CURRENT_TAG"-build >/dev/null 2>&1; then
    echo "Tag $CURRENT_TAG-build exists. Deleting..."
    quiet_git tag -d "$CURRENT_TAG"-build
    quiet_git push origin ":refs/tags/$CURRENT_TAG-build"
  fi

  echo "Deploy tag $CURRENT_TAG"
  quiet_git add --force docroot vendor hooks scripts drush config patches private .travis composer.*
  quiet_git commit -m "Pushing tag to $HOSTING_PLATFORM..."
  quiet_git tag -a "$CURRENT_TAG"-build -m "Deployment tag for $CURRENT_TAG"
  quiet_git push origin --tags
  echo "Tag deployment Success"
  exit 0
}

# Start of main script logic
cleanup
git clone "$REMOTE_GIT_REPO" "$ACQUIA_SUBFOLDER"
cd "$ACQUIA_SUBFOLDER" || exit

if [[ "$CURRENT_BRANCH" == release-* || "$CURRENT_BRANCH" == develop || "$CURRENT_BRANCH" == hotfix-* || "$CURRENT_BRANCH" == feature-* ]]; then
  push "$CURRENT_BRANCH"
elif [[ "$CURRENT_TAG" != "undefined" ]]; then
  remove_acquia_files
  rsync_files
  tag
else
  echo "Use proper branch name "
fi