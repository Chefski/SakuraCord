#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -gt 1 ]] || [[ "$#" -eq 1 && "$1" != "--offline" && "$1" != "--offline-sign-in" ]]; then
  echo "usage: $0 [--offline|--offline-sign-in]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=runtime.sh
source "$ROOT_DIR/script/runtime.sh"

sakuracord_acquire_operation_lock
trap sakuracord_release_operation_lock EXIT

if [[ ! -x "$SAKURACORD_EXECUTABLE_PATH" ]]; then
  echo "No built app at $SAKURACORD_APP_BUNDLE. Run ./script/build_and_run.sh package first." >&2
  exit 1
fi

sakuracord_stop_scoped_app
if [[ "$#" -eq 1 ]]; then
  /usr/bin/open -n "$SAKURACORD_APP_BUNDLE" --args "$1"
else
  /usr/bin/open -n "$SAKURACORD_APP_BUNDLE"
fi
sakuracord_wait_for_scoped_app
