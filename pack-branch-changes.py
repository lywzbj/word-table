#!/usr/bin/env python3
"""
Package changed files from the current branch into a tar.gz, preserving directory structure.

Two modes:
  1. -n N  : package only the last N commits' changes
  2. default: package all changes on the branch relative to the base branch

A CHANGELOG.md is included in the archive recording commit hashes, subjects, and per-commit file lists.

Usage: python pack-branch-changes.py [-n N] [-o output.tar.gz] [base-branch]
"""

import argparse
import datetime
import io
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
    r = subprocess.run(
        ["git", "remote", "show", "origin"], capture_output=True, text=True
    )
    if r.returncode == 0:
        for line in r.stdout.splitlines():
            if "HEAD branch" in line:
                branch = line.split(":")[-1].strip()
                return f"origin/{branch}"
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

    if base_branch is None:
        base_branch = detect_main_branch()
        if base_branch is None:
            print("Error: cannot auto-detect main branch, please specify manually", file=sys.stderr)
            sys.exit(1)
        print(f"→ Detected base branch: {base_branch}")

    diff = git("merge-base", "HEAD", base_branch)
    if diff is None:
        print(f"Error: cannot determine merge-base with {base_branch}", file=sys.stderr)
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


def build_changelog(commits: list[tuple[str, str, list[str]]], diff_base: str) -> str:
    """Build a CHANGELOG.md from commit info."""
    lines: list[str] = []
    lines.append("# Change Log\n\n")
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S %z")
    lines.append(f"Generated: {now}\n")
    branch = git("rev-parse", "--abbrev-ref", "HEAD") or "(detached)"
    lines.append(f"Branch: {branch}\n")
    short_base = git("rev-parse", "--short", diff_base) or diff_base[:7]
    lines.append(f"Diff base: {short_base}\n\n")
    lines.append(f"## Commits ({len(commits)})\n\n")
    for ch, subj, files in commits:
        short = git("rev-parse", "--short", ch) or ch[:7]
        lines.append(f"### {short} - {subj}\n\n")
        if files:
            lines.append("| File |\n|------|\n")
            for f in files:
                lines.append(f"| `{f}` |\n")
        else:
            lines.append("*(empty commit)*\n")
        lines.append("\n")
    return "".join(lines)


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

    # Gather per-commit info for the changelog
    commit_list: list[tuple[str, str, list[str]]] = []
    log_raw = git("log", "--format=%H%x09%s", f"{diff_base}..HEAD")
    if log_raw:
        for line in log_raw.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t", 1)
            ch = parts[0]
            subj = parts[1] if len(parts) > 1 else ""
            cf = git("diff-tree", "--no-commit-id", "-r", "--name-only", "--diff-filter=ACMR", ch)
            files = [f.strip() for f in cf.splitlines() if f.strip()] if cf else []
            commit_list.append((ch, subj, files))

    # Collect changed files (exclude deletions)
    print("→ Collecting changed files...")
    raw = git("diff", "--name-only", "--diff-filter=ACMR", diff_base, "HEAD")
    if not raw:
        print("→ No changed files")
        sys.exit(0)

    file_list = [f for f in raw.splitlines() if f.strip()]

    # Build changelog
    changelog = build_changelog(commit_list, diff_base)

    # Package
    print(f"→ Packaging to {args.o} ...")
    with tarfile.open(args.o, "w:gz") as tar:
        for f in file_list:
            tar.add(f, arcname=f)
        info = tarfile.TarInfo(name="CHANGELOG.md")
        encoded = changelog.encode("utf-8")
        info.size = len(encoded)
        tar.addfile(info, io.BytesIO(encoded))

    size = Path(args.o).stat().st_size
    print(f"Done: {args.o} ({format_size(size)}) — {len(file_list)} file(s)")


if __name__ == "__main__":
    main()
