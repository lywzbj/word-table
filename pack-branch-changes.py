#!/usr/bin/env python3
"""
提取当前分支变更文件并打包（保留目录结构）。

支持两种模式：
  1. -n N  : 只提取最近 N 个提交的变更
  2. 默认   : 提取当前分支相对于主分支（自动检测或手动指定）的全部变更

用法: python pack-branch-changes.py [-n N] [-o output.tar.gz] [base-branch]
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
            print("错误: -n 后必须是正整数", file=sys.stderr)
            sys.exit(1)
        diff = f"HEAD~{n}"
        if git("rev-parse", "--verify", diff) is None:
            print(
                f"错误：仓库历史不足 {n} 个提交（{diff} 不存在）",
                file=sys.stderr,
            )
            sys.exit(1)
        print(f"→ 提取最近 {n} 个提交的变更")
        return diff

    # Branch mode
    if base_branch is None:
        base_branch = detect_main_branch()
        if base_branch is None:
            print("错误：无法自动检测主分支，请手动指定", file=sys.stderr)
            sys.exit(1)
        print(f"→ 检测到主分支: {base_branch}")

    diff = git("merge-base", "HEAD", base_branch)
    if diff is None:
        print(
            f"错误：无法确定当前分支与 {base_branch} 的分叉点",
            file=sys.stderr,
        )
        sys.exit(1)

    short = git("rev-parse", "--short", diff) or diff[:7]
    print(f"→ 分叉点: {short}")
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
        description="提取当前分支变更文件并打包（保留目录结构）"
    )
    parser.add_argument("-n", type=int, help="只提取最近 N 个提交的变更")
    parser.add_argument(
        "-o",
        default="branch-changes.tar.gz",
        help="输出文件名（默认: branch-changes.tar.gz）",
    )
    parser.add_argument(
        "base_branch",
        nargs="?",
        help="主分支名，默认自动检测（main / master / origin HEAD）",
    )
    args = parser.parse_args()

    diff_base = resolve_diff_base(args.n, args.base_branch)

    # Collect changed files (exclude deletions)
    print("→ 收集变更文件...")
    raw = git("diff", "--name-only", "--diff-filter=ACMR", diff_base, "HEAD")
    if not raw:
        print("→ 没有变更文件")
        sys.exit(0)

    file_list = [f for f in raw.splitlines() if f.strip()]

    # Package with tarfile (cross-platform, no external tar needed)
    print(f"→ 打包到 {args.o} ...")
    with tarfile.open(args.o, "w:gz") as tar:
        for f in file_list:
            tar.add(f, arcname=f)

    size = Path(args.o).stat().st_size
    print(f"✅ 完成！{args.o} ({format_size(size)}) — 包含 {len(file_list)} 个文件")


if __name__ == "__main__":
    main()
