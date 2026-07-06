#!/usr/bin/env python3
"""
 Package changed files from the current branch into a tar.gz, preserving directory structure.
 
 Two modes:
   1. -n N  : package only the last N commits' changes
   2. default: package all changes on the branch relative to the base branch
 
 Usage: python pack-branch-changes.py [-n N] [-o output.tar.gz] [base-branch]
"""

import argparse
import subprocess
import sys
import tarfile
from pathlib import Path


def git(*args: str) -> str | None:
    """Run a git command and return stripped stdout, or None on failure."""
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def detect_main_branch() -> str | None:
    """Auto-detect the main branch name."""
    # Try remote default branch first
    r = subprocess.run(
        ["git", "remote", "show", "origin"], capture_output=True, text=True
    )
    if r.returncode == 0:
        for line in r.stdout.splitlines():
            if "HEAD branch" in line:
                branch = line.split(":")[-1].strip()
                return f"origin/{branch}"

    # Fall back to local main / master
    for name in ("main", "master"):
        r = subprocess.run(
            ["git", "show-ref", "--verify", "--quiet", f"refs/heads/{name}"]
        )
        if r.returncode == 0:
            return name

    return None


def resolve_diff_base(n: int | None, base_branch: str | None) -> str:
    """Determine the diff base (HEAD~N or merge-base)."""
    if n is not None:
        if n < 1:
            print("Error: -n must be a positive integer", file=sys.stderr)
            sys.exit(1)
        diff = f"HEAD~{n}"
        if git("rev-parse", "--verify", diff) is None:
            print(
                f"Error: not enough history for {n} commits ({diff} does not exist)",
                file=sys.stderr,
            )
            sys.exit(1)
        print(f"→ Packaging changes from last {n} commit(s)")
        return diff

    # Branch mode
    if base_branch is None:
        base_branch = detect_main_branch()
        if base_branch is None:
            print("Error: cannot auto-detect main branch, please specify manually", file=sys.stderr)
            sys.exit(1)
        print(f"→ Detected base branch: {base_branch}")

    diff = git("merge-base", "HEAD", base_branch)
    if diff is None:
        print(
            f"Error: cannot determine merge-base with {base_branch}",
            file=sys.stderr,
        )
        sys.exit(1)

    short = git("rev-parse", "--short", diff) or diff[:7]
    print(f"→ Merge base: {short}")
    return diff


def format_size(size: int) -> str:
    if size < 1024:
        return f"{size}B"
    elif size < 1048576:
        return f"{size // 1024}K"
    else:
        return f"{size // 1048576}M"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Package changed files from current branch into tar.gz"
    )
    parser.add_argument("-n", type=int, help="Only package the last N commits")
    parser.add_argument(
        "-o",
        default="branch-changes.tar.gz",
        help="Output filename (default: branch-changes.tar.gz)",
    )
    parser.add_argument(
        "base_branch",
        nargs="?",
        help="Base branch name (auto-detected if omitted: main/master/origin HEAD)",
    )
    args = parser.parse_args()

    diff_base = resolve_diff_base(args.n, args.base_branch)

    # Collect changed files (exclude deletions)
    print("→ Collecting changed files...")
    raw = git("diff", "--name-only", "--diff-filter=ACMR", diff_base, "HEAD")
    if not raw:
        print("→ No changed files")
        sys.exit(0)

    file_list = [f for f in raw.splitlines() if f.strip()]

    # Package with tarfile (cross-platform, no external tar needed)
    print(f"→ Packaging to {args.o} ...")
    with tarfile.open(args.o, "w:gz") as tar:
        for f in file_list:
            tar.add(f, arcname=f)

    size = Path(args.o).stat().st_size
    print(f"Done: {args.o} ({format_size(size)}) — {len(file_list)} file(s)")


if __name__ == "__main__":
    main()
