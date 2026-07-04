# provus-ci

Reusable CI/CD deploy scripts for Drupal sites hosted on **Pantheon** or
**Acquia**. Copy this repo's contents into a site repo (or pull it in as a
subtree/submodule) and wire up either GitHub Actions or Travis CI — both
drive the same platform scripts under `.ci/`, so switching CI providers or
hosting providers doesn't require rewriting deploy logic.

## Layout

```
.ci/
  .env                # shared config (hosting choice + non-secret settings)
  deploy.sh           # entry point: sources .env, normalizes CI vars, dispatches by $HOSTING
  pantheon/deploy.sh   # Pantheon deploy (Terminus, multidevs, config import)
  acquia/deploy.sh     # Acquia deploy (git-push artifact deploys)
hosting/pantheon/       # files copied into the build artifact for Pantheon
.github/workflows/deploy.yml   # GitHub Actions pipeline
.travis.yml                    # Travis CI pipeline
```

Both `pantheon/deploy.sh` and `acquia/deploy.sh` read `$BUILD_NUMBER` and
`$COMMIT_SHA` instead of provider-specific variables — `.ci/deploy.sh`
resolves these from whichever CI provider set them (`GITHUB_RUN_NUMBER`/
`GITHUB_SHA` on GitHub Actions, `TRAVIS_BUILD_NUMBER`/`TRAVIS_COMMIT` on
Travis), so the platform scripts stay CI-agnostic.

## Setup

1. Copy `.ci/`, `hosting/`, and one of `.github/workflows/deploy.yml` or
   `.travis.yml` into your site repo.
2. Edit `.ci/.env` and set `HOSTING` to `pantheon` or `acquia`, plus any of
   the non-secret settings documented inline (branch names, `KEEP_BRANCH`,
   `PANTHEON_IC`, `REMOTE_GIT_REPO`, etc).
3. Configure secrets with your CI provider — never commit these to `.ci/.env`.

### GitHub Actions

Set `env.PLATFORM` in `.github/workflows/deploy.yml` to `pantheon` or
`acquia`, then add these repo secrets:

| Platform | Secrets |
|---|---|
| Pantheon | `PANTHEON_KEY`, `PANTHEON_SSH_CONFIG`, `PANTHEON_KNOWN_HOSTS`, `PANTHEON_ENV`, `PANTHEON_REPO`, `PANTHEON_SITE_ID`, `SECRET_TERMINUS_TOKEN` |
| Acquia | `ACQUIA_KEY`, `ACQUIA_SSH_CONFIG`, `ACQUIA_KNOWN_HOSTS` |

### Travis CI

Set `HOSTING` in `.ci/.env` (Travis has no per-platform toggle like the
Actions workflow's `env.PLATFORM`), then add a **base64-encoded** SSH
deploy key as a hidden repo environment variable:

- Pantheon: `PANTHEON_KEY` — `base64 -i id_rsa | tr -d '\n'`
- Acquia: `ACQUIA_KEY` — same encoding

Travis automatically exposes `TRAVIS_BUILD_NUMBER`/`TRAVIS_COMMIT`, so no
extra build-metadata configuration is needed.

## Notes

- Pantheon deploys build an artifact commit and push it via Terminus
  build-tools; multidevs are created per build and torn down unless
  `KEEP_BRANCH=true`.
- Acquia deploys push directly to the Acquia git remote on
  `develop`/`feature-*`/`hotfix-*`/`release-*` branches and on tags.
- Set `PANTHEON_IC=true` in `.ci/.env` if the site uses Pantheon's
  Integrated Composer upstream (deploys `pantheon.upstream.yml` instead of
  `pantheon.yml`).
