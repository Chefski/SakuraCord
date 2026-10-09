#!/usr/bin/env bash
# Unprivileged CI only: never expose a signing key or repository write token here.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$ROOT_DIR/script/runtime.sh"
: "${GITHUB_RUN_ID:?}"
: "${GITHUB_RUN_ATTEMPT:?}"
: "${SPARKLE_ED_PUBLIC_KEY:?Set the public repository variable SPARKLE_ED_PUBLIC_KEY}"
export SAKURACORD_ENABLE_UPDATES=1
export SAKURACORD_INSECURE_DEBUG_CREDENTIALS=0
export SAKURACORD_CODE_SIGN_IDENTITY=-
export SAKURACORD_RELEASE_TRACK=nightly
if [[ ! "$GITHUB_RUN_ID" =~ ^[0-9]{1,13}$ || ! "$GITHUB_RUN_ATTEMPT" =~ ^[1-9][0-9]{0,2}$ ]]; then
  echo "Run identity exceeds the reserved PR version range." >&2
  exit 2
fi
export SAKURACORD_BUILD_NUMBER="$((4000000000000000000 + GITHUB_RUN_ID * 1000 + GITHUB_RUN_ATTEMPT))"
export SAKURACORD_PR_BUILD=1
# CI's shared release env contains the PR ref name, which is not a release tag.
unset SAKURACORD_RELEASE_TAG
"$ROOT_DIR/script/build_and_run.sh" package
BIN_DIR="$(swift build --package-path "$SAKURACORD_PACKAGE_DIR" \
  --cache-path "$SAKURACORD_SWIFTPM_CACHE_DIR" --scratch-path "$SAKURACORD_SCRATCH_DIR" \
  --show-bin-path)"
OUT="$ROOT_DIR/dist/pr-build"
mkdir -p "$OUT"
xcrun dsymutil "$BIN_DIR/SakuraCord" -o "$OUT/SakuraCord.app.dSYM"
codesign --verify --deep --strict "$SAKURACORD_APP_BUNDLE"
ditto -c -k --keepParent "$SAKURACORD_APP_BUNDLE" "$OUT/SakuraCord.app.zip"
ditto -c -k --keepParent "$OUT/SakuraCord.app.dSYM" "$OUT/SakuraCord.dSYM.zip"
cp "$SAKURACORD_APP_BUNDLE/Contents/Resources/pr-build.json" "$OUT/build.json"
rm -rf "$OUT/SakuraCord.app.dSYM"
