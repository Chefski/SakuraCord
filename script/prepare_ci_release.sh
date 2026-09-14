#!/usr/bin/env bash
set -euo pipefail

release_tag="$SAKURACORD_RELEASE_TAG"
if ! git rev-parse --verify --quiet "refs/tags/$release_tag" >/dev/null; then
  echo "Release tag $release_tag does not exist." >&2
  exit 1
fi
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "refs/tags/$release_tag^{commit}")" ]]; then
  echo "Checkout does not match the release tag commit." >&2
  exit 1
fi
release_control_root="$GITHUB_WORKSPACE"
if [[ "$GITHUB_EVENT_NAME" == "workflow_dispatch" ]]; then
  release_control_root="$GITHUB_WORKSPACE/release-control"
fi
source "$release_control_root/script/release_metadata.sh"
if ! sakuracord_is_release_tag "$release_tag"; then
  echo "Release tags must use vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-Beta-NUMBER." >&2
  exit 1
fi
version="$(sakuracord_release_version_from_tag "$release_tag")"
release_track="$(sakuracord_release_track_from_tag "$release_tag")"
release_display_name="$(sakuracord_release_display_name_from_tag "$release_tag")"
dmg_name="$(sakuracord_release_dmg_name_from_tag "$release_tag")"
git fetch --no-tags origin \
  +refs/heads/nightly:refs/remotes/origin/nightly
if ! git merge-base --is-ancestor \
  "refs/tags/$release_tag^{commit}" refs/remotes/origin/nightly; then
  if [[ "$release_track" == "nightly" ]]; then
    echo "Nightly beta tags must point to a commit on the nightly branch." >&2
  else
    echo "Regular release tags must point to a commit already present on nightly." >&2
  fi
  exit 1
fi
release_copy="$release_control_root/Releases/$release_tag.json"
if [[ ! -f "$release_copy" ]]; then
  echo "Releases/$release_tag.json must be written, reviewed, and committed before publishing." >&2
  exit 1
fi
"$release_control_root/script/validate_release_tag.sh" \
  "$release_control_root" "$release_tag"
echo "SAKURACORD_VERSION=$version" >> "$GITHUB_ENV"
echo "SAKURACORD_BUILD_NUMBER=$GITHUB_RUN_NUMBER" >> "$GITHUB_ENV"
echo "SAKURACORD_RELEASE_TAG=$release_tag" >> "$GITHUB_ENV"
echo "SAKURACORD_RELEASE_TRACK=$release_track" >> "$GITHUB_ENV"
echo "SAKURACORD_RELEASE_DISPLAY_NAME=$release_display_name" >> "$GITHUB_ENV"
echo "SAKURACORD_RELEASE_CONTROL_ROOT=$release_control_root" >> "$GITHUB_ENV"
echo "SAKURACORD_RELEASE_COPY=$release_copy" >> "$GITHUB_ENV"
echo "SAKURACORD_DMG_PATH=dist/$dmg_name" >> "$GITHUB_ENV"

published=false
announced=false
announcement_message_id=""
if gh release view "$release_tag" >/dev/null 2>&1; then
  release_state="$(gh release view "$release_tag" --json isDraft,isPrerelease)"
  is_draft="$(jq -r .isDraft <<< "$release_state")"
  is_prerelease="$(jq -r .isPrerelease <<< "$release_state")"
  expected_prerelease=false
  if [[ "$release_track" == "nightly" ]]; then
    expected_prerelease=true
  fi
  if [[ "$is_prerelease" != "$expected_prerelease" ]]; then
    echo "Existing release prerelease state does not match $release_track track." >&2
    exit 1
  fi
  if [[ "$is_draft" == "false" ]]; then
    published=true
  fi
  checkpoint_dir="$RUNNER_TEMP/release-checkpoints"
  mkdir -p "$checkpoint_dir"
  if gh release download "$release_tag" \
    --pattern discord-announcement.json --dir "$checkpoint_dir" >/dev/null 2>&1; then
    checkpoint_file="$checkpoint_dir/discord-announcement.json"
    if ! jq -e \
      --arg tag "$release_tag" \
      '.schemaVersion == 1 and .tagName == $tag and (.messageId | test("^[0-9]{17,20}$"))' \
      "$checkpoint_file" >/dev/null; then
      echo "Existing Discord announcement checkpoint is invalid." >&2
      exit 1
    fi
    announced=true
    announcement_message_id="$(jq -r .messageId "$checkpoint_file")"
  fi
fi
echo "published=$published" >> "$GITHUB_OUTPUT"
echo "announced=$announced" >> "$GITHUB_OUTPUT"
echo "announcement_message_id=$announcement_message_id" >> "$GITHUB_OUTPUT"
