#!/bin/bash
set -euo pipefail

CURRENT_BRANCH=$(git name-rev --name-only HEAD || echo "unknown")
CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null | sed 's/\^0//g' || echo "undefined")

composer install --no-interaction --no-progress

SITE_ROOT=$(pwd)
ACQUIA_SUBFOLDER="$GITHUB_WORKSPACE/TMP_ACQUIA"

quiet_git() {
  local stdout
  local stderr
  stdout=$(mktemp)
  stderr=$(mktemp)

  if ! git "$@" </dev/null >"$stdout" 2>"$stderr"; then
      cat "$stderr" >&2
      rm -f "$stdout" "$stderr"
      exit 1
  fi
  rm -f "$stdout" "$stderr"
}

remove_acquia_files() {
    rm -rf "$ACQUIA_SUBFOLDER/vendor" "$ACQUIA_SUBFOLDER/web"
}

cleanup() {
    echo "Cleaning up"
    rm -rf "$SITE_ROOT/tests" "$SITE_ROOT/BEHAT/" "$SITE_ROOT/.git*"
    find docroot/ vendor/ -type d -name ".git" -prune -exec rm -rf {} +
}

rsync_files() {
  echo "Rsync of files ongoing"
  echo "---------------------------------------"
  rsync -a --stats "$SITE_ROOT"/  "$ACQUIA_SUBFOLDER"/
  echo "---------------------------------------"
}

push() {
  git fetch --all
  local add_build="${1}-build"
  echo "PUSH"

  if git ls-remote --heads origin "$add_build" | grep -q "$add_build"; then
    git checkout "$add_build"
  else
    git checkout -b "$add_build"
  fi

  remove_acquia_files
  rsync_files

  quiet_git add --force docroot vendor hooks scripts drush config patches private  composer.*
  quiet_git commit -q -m "Build for $add_build" || echo "No changes to commit"
  echo "Pushing to Acquia..."
  git push origin "$add_build" --force
}

tag() {
  git fetch --all
  echo "Checking if tag exists"

  if git rev-parse "$CURRENT_TAG" >/dev/null 2>&1; then
    echo "Tag $CURRENT_TAG exists. Deleting..."
    quiet_git tag -d "$CURRENT_TAG"
    quiet_git push origin ":refs/tags/$CURRENT_TAG"
  fi

  echo "Deploy tag $CURRENT_TAG"
  quiet_git add --force docroot vendor hooks scripts drush config patches private  composer.*
  quiet_git commit -m "Pushing tag to Acquia..." || echo "No changes to commit"
  quiet_git tag -a "$CURRENT_TAG" -m "Deployment tag for $CURRENT_TAG"
  quiet_git push origin --tags
  echo "Tag deployment success"
}

# ------------------------
# Start of main script logic
# ------------------------

cleanup

# Ensure REMOTE_GIT_REPO is set
if [ -z "${REMOTE_GIT_REPO:-}" ]; then
  echo "❌ REMOTE_GIT_REPO is not set"
  exit 1
fi

rm -rf "$ACQUIA_SUBFOLDER"
git clone "$REMOTE_GIT_REPO" "$ACQUIA_SUBFOLDER"
cd "$ACQUIA_SUBFOLDER" || exit

if [[ "$CURRENT_BRANCH" == release-* || "$CURRENT_BRANCH" == develop || "$CURRENT_BRANCH" == hotfix-* || "$CURRENT_BRANCH" == feature-* ]]; then
  push "$CURRENT_BRANCH"
elif [[ "$CURRENT_TAG" != "undefined" ]]; then
  remove_acquia_files
  rsync_files
  tag
else
  echo "❌ Use proper branch name "
fi

