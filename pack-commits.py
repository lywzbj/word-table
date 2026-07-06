#!/usr/bin/env python3
"""
Package changed files from specified commits into a tar.gz, preserving directory structure.

If the same file appears in multiple specified commits, the version from the most recent
commit (by commit date) is kept.

A CHANGELOG.md is included in the archive recording commit hashes, subjects, and per-commit file lists.

Usage: python pack-commits.py [-o output.tar.gz] <commit1> [commit2] [...]
"""

import argparse
import datetime
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


def git_text(*args: str) -> str | None:
    """Run git, return stripped stdout text, or None on failure."""
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def git_bytes(*args: str) -> bytes | None:
    """Run git, return raw stdout bytes, or None on failure."""
    r = subprocess.run(["git", *args], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def format_size(size: int) -> str:
    if size < 1024:
        return f"{size}B"
    elif size < 1048576:
        return f"{size // 1024}K"
    else:
        return f"{size // 1048576}M"


def build_changelog(commits: list[str], files_map: dict[str, list[str]]) -> str:
    """Build a CHANGELOG.md from commit info."""
    lines: list[str] = []
    lines.append("# Change Log\n\n")
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S %z")
    lines.append(f"Generated: {now}\n")
    branch = git_text("rev-parse", "--abbrev-ref", "HEAD") or "(detached)"
    lines.append(f"Branch: {branch}\n\n")
    lines.append(f"## Commits ({len(commits)})\n\n")
    for ch in commits:
        short = git_text("rev-parse", "--short", ch) or ch[:7]
        subj = git_text("log", "--format=%s", "-n1", ch) or ""
        lines.append(f"### {short} - {subj}\n\n")
        files = files_map.get(ch, [])
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
        description="Package changed files from specified commits into tar.gz"
    )
    parser.add_argument(
        "-o",
        default="commits-changes.tar.gz",
        help="Output filename (default: commits-changes.tar.gz)",
    )
    parser.add_argument(
        "commits", nargs="+", help="One or more commit hashes (short or full)"
    )
    args = parser.parse_args()

    for c in args.commits:
        if git_text("cat-file", "-e", f"{c}^{{commit}}") is None:
            print(f"Error: {c} is not a valid commit", file=sys.stderr)
            sys.exit(1)

    print("→ Resolving commits...")
    sorted_raw = git_text(
        "rev-list", "--no-walk", "--date-order", "--reverse", *args.commits
    )
    if not sorted_raw:
        print("Error: unable to resolve commits", file=sys.stderr)
        sys.exit(1)
    sorted_commits = sorted_raw.splitlines()

    commit_files_map: dict[str, list[str]] = {}

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)

        for commit in sorted_commits:
            short = git_text("rev-parse", "--short", commit) or commit[:7]
            print(f"→ Processing {short} ...")

            files_raw = git_text(
                "diff-tree",
                "--no-commit-id",
                "-r",
                "--name-only",
                "--diff-filter=ACMR",
                commit,
            )
            per_commit_files: list[str] = []
            if not files_raw:
                commit_files_map[commit] = []
                continue

            for rel_path in files_raw.splitlines():
                rel_path = rel_path.strip()
                if not rel_path:
                    continue
                per_commit_files.append(rel_path)

                target = tmp / rel_path
                target.parent.mkdir(parents=True, exist_ok=True)

                content = git_bytes("show", f"{commit}:{rel_path}")
                if content is not None:
                    target.write_bytes(content)
                else:
                    print(f"  Warning: cannot extract {rel_path}")

            commit_files_map[commit] = per_commit_files

        file_count = sum(1 for f in tmp.rglob("*") if f.is_file())
        if file_count == 0:
            print("→ No changed files in the specified commits")
            sys.exit(0)

        # Build and write changelog into the temp dir so it gets packaged
        changelog = build_changelog(sorted_commits, commit_files_map)
        (tmp / "CHANGELOG.md").write_text(changelog, encoding="utf-8")

        print(f"→ Packaging to {args.o} ...")
        with tarfile.open(args.o, "w:gz") as tar:
            for f in tmp.rglob("*"):
                if f.is_file():
                    tar.add(f, arcname=f.relative_to(tmp))

        size = Path(args.o).stat().st_size
        print(
            f"Done: {args.o} ({format_size(size)})"
            f" — {len(sorted_commits)} commit(s), {file_count} unique file(s)"
        )


if __name__ == "__main__":
    main()
