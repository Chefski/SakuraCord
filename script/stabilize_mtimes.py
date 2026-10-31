#!/usr/bin/env python3
"""Give tracked files content-derived modification times.

A fresh CI checkout stamps every file with the current time, so restored
SwiftPM build outputs look stale and every module recompiles. SwiftPM treats a
file as unchanged only when its size and modification time both match the
recorded values, so deriving the time from the Git blob hash makes identical
content look identical across checkouts while any content change still moves
the time. Each argument is a Git work tree, such as the repository root or a
SwiftPM dependency checkout.
"""

import os
import subprocess
import sys

# Spread times over roughly 2001-2009; build outputs are always newer.
EPOCH = 1_000_000_000
SPAN = 1 << 28


def stabilize(work_tree):
    listing = subprocess.run(
        ["git", "-C", work_tree, "ls-files", "--stage", "-z"],
        check=True,
        capture_output=True,
    ).stdout
    count = 0
    for entry in listing.split(b"\0"):
        if not entry:
            continue
        metadata, path = entry.split(b"\t", 1)
        mode, blob, _ = metadata.split(b" ")
        full_path = os.path.join(os.fsencode(work_tree), path)
        if mode == b"160000":
            # Dependencies such as libwebp-Xcode vendor sources as submodules.
            if os.path.exists(os.path.join(full_path, b".git")):
                count += stabilize(os.fsdecode(full_path))
            continue
        mtime = EPOCH + int(blob[:7], 16) % SPAN
        try:
            os.utime(full_path, (mtime, mtime), follow_symlinks=False)
            count += 1
        except FileNotFoundError:
            pass
    return count


def main(work_trees):
    if not work_trees:
        print("usage: stabilize_mtimes.py WORK_TREE [WORK_TREE ...]", file=sys.stderr)
        return 2
    for work_tree in work_trees:
        print(f"Stabilized {stabilize(work_tree)} file times in {work_tree}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
