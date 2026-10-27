#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REMOTE="${1:-origin}"
MAIN_REF="refs/remotes/$REMOTE/main"
NIGHTLY_REF="refs/remotes/$REMOTE/nightly"

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
  echo "Main-to-nightly synchronization requires a clean worktree." >&2
  exit 2
fi

git -C "$ROOT_DIR" fetch --no-tags "$REMOTE" \
  "+refs/heads/main:$MAIN_REF" \
  "+refs/heads/nightly:$NIGHTLY_REF"

# Without a GitHub token, gh or a successful run, nightly counts as unvalidated.
nightly_ci_passed() {
  [[ -n "${GITHUB_REPOSITORY:-}" ]] && command -v gh >/dev/null || return 1
  local commit runs
  commit="$(git -C "$ROOT_DIR" rev-parse "$NIGHTLY_REF")"
  runs="$(gh run list --repo "$GITHUB_REPOSITORY" --workflow ci.yml \
    --commit "$commit" --status success --limit 1 \
    --json databaseId --jq length 2>/dev/null || true)"
  [[ "$runs" == 1 ]]
}

if git -C "$ROOT_DIR" merge-base --is-ancestor "$MAIN_REF" "$NIGHTLY_REF"; then
  echo "Nightly already contains main."
  exit 0
fi

git -C "$ROOT_DIR" switch --force-create nightly "$NIGHTLY_REF"
git -C "$ROOT_DIR" config user.name "github-actions[bot]"
git -C "$ROOT_DIR" config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if git -C "$ROOT_DIR" merge-base --is-ancestor "$NIGHTLY_REF" "$MAIN_REF"; then
  git -C "$ROOT_DIR" merge --ff-only "$MAIN_REF"
else
  git -C "$ROOT_DIR" merge --no-edit "$MAIN_REF"
  # A main commit whose changes nightly already has, such as a hotfix copied
  # from nightly, leaves nightly's tree unchanged; that tree needs no second
  # validation once CI has passed for nightly's exact commit.
  if [[ "$(git -C "$ROOT_DIR" rev-parse 'HEAD^{tree}')" != \
    "$(git -C "$ROOT_DIR" rev-parse "$NIGHTLY_REF^{tree}")" ]] \
    || ! nightly_ci_passed; then
    "$ROOT_DIR/script/ci.sh"
  fi
fi

if ! git -C "$ROOT_DIR" merge-base --is-ancestor "$MAIN_REF" HEAD; then
  echo "The synchronized nightly commit does not contain main." >&2
  exit 1
fi

git -C "$ROOT_DIR" push "$REMOTE" HEAD:refs/heads/nightly
printf 'Synchronized nightly with %s.\n' "$(git -C "$ROOT_DIR" rev-parse --short "$MAIN_REF")"
