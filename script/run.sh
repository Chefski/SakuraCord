#!/usr/bin/env bash
set -euo pipefail

CONTROL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROOT_DIR="$CONTROL_ROOT"
BUILD=0
LAUNCH_ARGS=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --checkout)
      [[ "$#" -ge 2 ]] || { echo "--checkout requires a directory." >&2; exit 2; }
      ROOT_DIR="$(cd "$2" && pwd -P)"
      shift 2
      ;;
    --build) BUILD=1; shift ;;
    --offline|--offline-sign-in) LAUNCH_ARGS=(--args "$1"); shift ;;
    *)
      echo "usage: $0 [--checkout PATH] [--build] [--offline|--offline-sign-in]" >&2
      exit 2
      ;;
  esac
done

SAKURACORD_ROOT_DIR="$ROOT_DIR"
# shellcheck source=runtime.sh
source "$CONTROL_ROOT/script/runtime.sh"

if [[ "$BUILD" == "1" ]]; then
  sakuracord_resolve_insecure_debug_credentials "$ROOT_DIR"
  sakuracord_apply_secure_release_credential_policy package "${SAKURACORD_ENABLE_UPDATES:-0}"
  sakuracord_resolve_code_sign_identity 1
  # Older packagers may ignore machine preferences. Pass the resolved values
  # explicitly and retain launch ownership in this current, guarded runtime.
  SAKURACORD_ROOT_DIR="$ROOT_DIR" \
    SAKURACORD_INSECURE_DEBUG_CREDENTIALS="$SAKURACORD_RESOLVED_INSECURE_DEBUG_CREDENTIALS" \
    SAKURACORD_CODE_SIGN_IDENTITY="$SAKURACORD_RESOLVED_CODE_SIGN_IDENTITY" \
    "$ROOT_DIR/script/build_and_run.sh" package
fi

sakuracord_acquire_operation_lock
trap sakuracord_release_operation_lock EXIT

if [[ ! -x "$SAKURACORD_EXECUTABLE_PATH" ]]; then
  echo "No built app at $SAKURACORD_APP_BUNDLE. Run ./script/build_and_run.sh package first." >&2
  exit 1
fi

sakuracord_launch_scoped_app ${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}
