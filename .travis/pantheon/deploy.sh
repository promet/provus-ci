#!/usr/bin/env bash

CURRENT_BRANCH=`git name-rev --name-only HEAD`
TERMINUS_BIN=scripts/bin/terminus

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

# Update the pantheon sites, updb, cim and clear the cache.
update_site() {
sleep 120
  echo "========================================="
  echo "...Clearing caches"
  echo "========================================="
  $TERMINUS_BIN env:clear-cache $PANTHEON_SITE_ID.$P_ENV
  echo "========================================="
  echo "...Importing config"
  echo "========================================="
  $TERMINUS_BIN drush -n $PANTHEON_SITE_ID.$P_ENV cim -y
  echo "========================================="
  echo "...Running update DB"
  echo "========================================="
  $TERMINUS_BIN drush -n $PANTHEON_SITE_ID.$P_ENV updb -y
}

# delete files we don't want on Pantheon and copy in some that we do.
clean_artifacts() {
  echo "========================================="
  echo "...Generating site artifacts"
  echo "========================================="
  cp hosting/pantheon/* .
  rm -rf .docksal
  rm -rf web/sites/default/files
  rm -rf hosting
}


echo "Logging into Terminus"
$TERMINUS_BIN auth:login --machine-token=$SECRET_TERMINUS_TOKEN
$TERMINUS_BIN connection:set $PANTHEON_SITE_ID.$PANTHEON_ENV git -y

echo "Add pantheon repo"
git remote add pantheon $PANTHEON_REPO

echo "Waking Pantheon $PANTHEON_SITE_ID Dev environment."
$TERMINUS_BIN env:wake -n $PANTHEON_SITE_ID.$PANTHEON_ENV

echo "... Pulling git"
git pull

echo "...Run composer install"
composer install

echo "...remove nested .git dirs from web and vendor directories recursively"
find web/ | grep .git | xargs rm -rf
find vendor/ | grep .git | xargs rm -rf



if [ "$CURRENT_BRANCH" != "$PANTHEON_ENV" ]; then
  echo "========================================="
  echo "...Building Branch on new Multidev"
  echo "========================================="
  echo "...Delete MD if it already exists"
  $TERMINUS_BIN multidev:delete $PANTHEON_SITE_ID.ci-$TRAVIS_BUILD_NUMBER --delete-branch --yes
  echo "...Building Mutlidev ci-$TRAVIS_BUILD_NUMBER"
  $TERMINUS_BIN multidev:create $PANTHEON_SITE_ID.$PANTHEON_ENV ci-$TRAVIS_BUILD_NUMBER --yes

  # Clean up the codebase before sending
  clean_artifacts

  echo "...Switch to new ci-$TRAVIS_BUILD_NUMBER branch locally"
  git checkout -b ci-$TRAVIS_BUILD_NUMBER
  echo "...Add the new files"
  quiet_git add -f vendor/* web/* pantheon* config/*
  quiet_git commit -m "Artifacts for build ci-$TRAVIS_BUILD_NUMBER"
  echo "...Push to pantheon"
  git push pantheon ci-$TRAVIS_BUILD_NUMBER --force
  P_ENV="ci-$TRAVIS_BUILD_NUMBER"
  update_site "$P_ENV"

else

  echo "========================================="
  echo "...Updating Develop Branch"
  echo "========================================="

  git checkout -b ci-$TRAVIS_BUILD_NUMBER

  # Clean up the codebase before sending
  clean_artifacts

  echo "...Add the new files"
  quiet_git add -f vendor/* web/* pantheon* config/*
  echo "...Committig and pushing to Pantheon"
  quiet_git commit -m "TRAVIS JOB: $TRAVIS_JOB_ID - $TRAVIS_COMMIT_MESSAGE"
  echo "...Push to pantheon"
  git push pantheon ci-$TRAVIS_BUILD_NUMBER:$PANTHEON_ENV --force
  # set this for doing things on Pantheon later.
  P_ENV=$PANTHEON_ENV
  # Run site updates.
  update_site "$P_ENV"
fi

# if we're only testing delete the MD used for said tests.
if [ "$CURRENT_BRANCH" != "$PANTHEON_ENV" ]; then
 $TERMINUS_BIN multidev:delete $PANTHEON_SITE_ID.ci-$TRAVIS_BUILD_NUMBER --delete-branch --yes
fi

