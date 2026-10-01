#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
SNAPSHOT_PARENT="$ROOT_DIR/.build/pre-push-snapshots"
mkdir -p "$SNAPSHOT_PARENT"
TEMP_ROOT="$(mktemp -d "$SNAPSHOT_PARENT/run.XXXXXX")"
ZERO_SHA="0000000000000000000000000000000000000000"
SEEN_SHAS=""
CHECKED_REF_COUNT=0
BASE_REF="refs/sakuracord/code-quality/$(basename "$TEMP_ROOT")"
BASE_SHA=""
SEEN_MERGES=""

cleanup() {
  git update-ref -d "$BASE_REF"
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

check_snapshot() {
  local snapshot_root="$1"
  local label="$2"

  "$ROOT_DIR/script/check_code_quality_snapshot.sh" \
    "$snapshot_root" \
    "Pre-push code quality: $label"
}

check_commit() {
  local sha="$1"
  local snapshot_root="$TEMP_ROOT/commit-$sha"

  if [[ "$SEEN_SHAS" == *"|$sha|"* ]]; then
    return
  fi
  SEEN_SHAS="$SEEN_SHAS|$sha|"

  mkdir -p "$snapshot_root"
  git archive "$sha" | tar -x -C "$snapshot_root"
  check_snapshot "$snapshot_root" "committed tree $sha"
  CHECKED_REF_COUNT=$((CHECKED_REF_COUNT + 1))
}

check_release_copy() {
  local sha="$1"
  local tag="$2"
  local snapshot_root="$TEMP_ROOT/commit-$sha"

  "$snapshot_root/script/validate_release_tag.sh" "$snapshot_root" "$tag"
}

check_pull_request_merge() {
  local sha="$1"
  local result
  local tree
  local snapshot_root

  if [[ "$SEEN_MERGES" == *"|$sha|"* ]]; then
    return
  fi
  SEEN_MERGES="$SEEN_MERGES|$sha|"

  # Repository policy targets feature PRs at canonical nightly, including
  # branches pushed to forks. Fetch once per push instead of trusting a stale
  # tracking ref. A private ref preserves the caller's FETCH_HEAD and branches.
  if [[ -z "$BASE_SHA" ]]; then
    if ! git fetch --no-tags --no-write-fetch-head \
      https://github.com/SakuraCordApp/SakuraCord.git \
      "refs/heads/nightly:$BASE_REF"; then
      echo "Could not fetch nightly for pre-push merge validation." >&2
      return 1
    fi
    BASE_SHA="$(git rev-parse "$BASE_REF")"
  fi
  if ! result="$(git merge-tree --write-tree "$BASE_SHA" "$sha")"; then
    echo "Cannot merge pushed commit $sha with nightly $BASE_SHA:" >&2
    echo "$result" >&2
    return 1
  fi
  tree="${result%%$'\n'*}"
  snapshot_root="$TEMP_ROOT/merge-$sha"
  mkdir -p "$snapshot_root"
  git archive "$tree" | tar -x -C "$snapshot_root"
  check_snapshot "$snapshot_root" "commit $sha merged with nightly $BASE_SHA"
}

while read -r local_ref local_sha remote_ref remote_sha; do
  if [[ -z "${local_ref:-}" || "$local_sha" == "$ZERO_SHA" ]]; then
    continue
  fi
  check_commit "$local_sha"
  case "$remote_ref" in
    refs/heads/main|refs/heads/nightly) ;;
    refs/heads/*) check_pull_request_merge "$local_sha" ;;
  esac
  if [[ "$remote_ref" == refs/tags/v* ]]; then
    check_release_copy "$local_sha" "${remote_ref#refs/tags/}"
  fi
done

if ! git diff --cached --quiet --diff-filter=ACMR -- '*.swift'; then
  INDEX_ROOT="$TEMP_ROOT/index"
  mkdir -p "$INDEX_ROOT"
  git checkout-index --all --prefix="$INDEX_ROOT/"
  check_snapshot "$INDEX_ROOT" "staged Swift snapshot"
fi

if [[ "$CHECKED_REF_COUNT" -eq 0 ]] \
  && git diff --cached --quiet --diff-filter=ACMR -- '*.swift'; then
  echo "Pre-push code quality: no pushed ref or staged Swift change required checking."
fi
