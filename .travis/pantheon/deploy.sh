#!/usr/bin/env bash

CURRENT_BRANCH=`git name-rev --name-only HEAD`
CURRENT_TAG=`git name-rev --tags --name-only $(git rev-parse HEAD)`
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
  $TERMINUS_BIN env:clear-cache $PANTHEON_SITE_ID.$1
   # if it fails - report the fail and
  check_error "$?"

  echo "========================================="
  echo "...Importing config"
  echo "========================================="
  $TERMINUS_BIN drush -n $PANTHEON_SITE_ID.$1 cim -y
  # if it fails - report the fail and
  check_error "$?"

  echo "========================================="
  echo "...Running update DB"
  echo "========================================="
  $TERMINUS_BIN drush -n $PANTHEON_SITE_ID.$1 updb -y
 # if it fails - report the fail and
  check_error "$?"
}

check_error() {
   if [ $1 -ne 0 ]; then
    echo "========================================="
    echo "...Build failure.. Deleting MD if created"
    echo "========================================="
    delete_md
    exit 1
  fi
}

# Update the UUID of the site to match the incoming config UUID
update_uuid() {
  sleep 60
  UUID=$(awk '{for (I=1;I<=NF;I++) if ($I == "uuid:") {print $(I+1)};}' config/default/system.site.yml)
  echo "...Setting site UUID to $UUID"
  $TERMINUS_BIN drush -n $PANTHEON_SITE_ID.$1 cset system.site uuid ${UUID} -y
  # if it fails - report the fail and
  check_error "$?"
}

# delete files we don't want on Pantheon and copy in some that we do.
clean_artifacts() {
  make_heading "...Generating site artifacts"

  cp hosting/pantheon/pantheon.upstream.yml .
  cp hosting/pantheon/pantheon.yml .
  cp hosting/pantheon/settings.pantheon.php web/sites/default/
  rm -rf .docksal
  rm -rf web/sites/default/files
  rm -rf hosting
}

make_heading() {
  echo "========================================="
  echo "...$1"
  echo "========================================="
}

remove_nests_git() {
  find web/ | grep .git | xargs rm -rf
  find vendor/ | grep .git | xargs rm -rf
}

delete_md() {
   if [[ "$CURRENT_BRANCH" != "$PANTHEON_ENV" && "$KEEP_BRANCH" != "$CURRENT_BRANCH" ]]; then
    $TERMINUS_BIN multidev:delete $PANTHEON_SITE_ID.ci-$TRAVIS_BUILD_NUMBER --delete-branch --yes
    # if it fails - report the fail and
    check_error "$?"
  fi
}

make_heading "Starting Build"

echo "Logging into Terminus"
$TERMINUS_BIN auth:login --machine-token=$SECRET_TERMINUS_TOKEN
$TERMINUS_BIN connection:set $PANTHEON_SITE_ID.$PANTHEON_ENV git -y

echo "Add pantheon repo"
git remote add pantheon $PANTHEON_REPO

echo "Waking Pantheon $PANTHEON_SITE_ID Dev environment."
$TERMINUS_BIN env:wake -n $PANTHEON_SITE_ID.$PANTHEON_ENV

make_heading "... Pulling git from $CURRENT_BRANCH"
git pull

echo "...Run composer install"
composer install

echo "...remove nested .git dirs from web and vendor directories recursively"
remove_nests_git

if [ $CURRENT_TAG != "undefined" ]; then
  make_heading "...Preparing for production deploy, fingers crossed!"
  git checkout -b ci-$TRAVIS_BUILD_NUMBER
  clean_artifacts
  quiet_git add -f vendor/* web/* pantheon* config/*
  quiet_git commit -m "DEPLOY: Build $CURRENT_TAG"
  echo "...Push to pantheon"
  git push pantheon ci-$TRAVIS_BUILD_NUMBER:$REMOTE_PROD_BRANCH --force
  make_heading "branch: $REMOTE_PROD_BRANCH"
  update_uuid "$REMOTE_PROD_ENV"
  update_site "$REMOTE_PROD_ENV"

else
  if [ "$CURRENT_BRANCH" != "$PANTHEON_ENV" ]; then
    make_heading "...Building Branch on new Multidev"

    echo "...Delete MD if it already exists"
    $TERMINUS_BIN multidev:delete $PANTHEON_SITE_ID.ci-$TRAVIS_BUILD_NUMBER --delete-branch --yes
    # if it fails - report the fail and
    #check_error "$?"

    echo "...Building Mutlidev ci-$TRAVIS_BUILD_NUMBER"
    $TERMINUS_BIN multidev:create $PANTHEON_SITE_ID.$PANTHEON_ENV ci-$TRAVIS_BUILD_NUMBER --yes
    # if it fails - report the fail and
    check_error "$?"

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
    #clean up / Site updates.
    update_uuid "$P_ENV"
    update_site "$P_ENV"

  elif   [ "$CURRENT_BRANCH" == "$DEVELOP_BRANCH" ]; then

    make_heading "...Updating Develop Branch"

    git checkout -b ci-$TRAVIS_BUILD_NUMBER

    # Clean up the codebase before sending
    clean_artifacts

    echo "...Add the new files"
    quiet_git add -f vendor/* web/* pantheon* config/*
    echo "...Committig and pushing to Pantheon"
    quiet_git commit -m "TRAVIS JOB: $TRAVIS_BUILD_NUMBER - ID: $TRAVIS_JOB_ID - $TRAVIS_COMMIT_MESSAGE"
    echo "...Push to pantheon"
    git push pantheon ci-$TRAVIS_BUILD_NUMBER:$PANTHEON_ENV --force
    # set this for doing things on Pantheon later.
    P_ENV=$PANTHEON_ENV
    # Run site updates.
    update_uuid "$P_ENV"
    update_site "$P_ENV"
  else
    make_heading "... No buildable branches detected"
  fi

  delete_md
fi
