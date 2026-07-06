#!/usr/bin/env python3
"""
提取指定提交（可不连续）的变更文件并打包（保留目录结构）。

同一文件在多个指定提交中出现时，保留提交时间上最新的版本。

用法: python pack-commits.py [-o output.tar.gz] <commit1> [commit2] [...]
"""

import argparse
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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="提取指定提交（可不连续）的变更文件并打包"
    )
    parser.add_argument(
        "-o",
        default="commits-changes.tar.gz",
        help="输出文件名（默认: commits-changes.tar.gz）",
    )
    parser.add_argument(
        "commits", nargs="+", help="一个或多个提交哈希（支持短哈希和完整哈希）"
    )
    args = parser.parse_args()

    # Validate every commit
    for c in args.commits:
        if git_text("cat-file", "-e", f"{c}^{{commit}}") is None:
            print(f"错误：{c} 不是有效的提交", file=sys.stderr)
            sys.exit(1)

    # Sort commits by date (oldest first — later commits overwrite earlier ones)
    print("→ 解析提交...")
    sorted_raw = git_text(
        "rev-list", "--no-walk", "--date-order", "--reverse", *args.commits
    )
    if not sorted_raw:
        print("错误：无法解析提交", file=sys.stderr)
        sys.exit(1)
    sorted_commits = sorted_raw.splitlines()

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)

        for commit in sorted_commits:
            short = git_text("rev-parse", "--short", commit) or commit[:7]
            print(f"→ 处理 {short} ...")

            # List files changed in this commit
            files_raw = git_text(
                "diff-tree",
                "--no-commit-id",
                "-r",
                "--name-only",
                "--diff-filter=ACMR",
                commit,
            )
            if not files_raw:
                continue

            for rel_path in files_raw.splitlines():
                rel_path = rel_path.strip()
                if not rel_path:
                    continue

                target = tmp / rel_path
                target.parent.mkdir(parents=True, exist_ok=True)

                content = git_bytes("show", f"{commit}:{rel_path}")
                if content is not None:
                    target.write_bytes(content)
                else:
                    print(f"  警告：无法提取 {rel_path}")

        # Count unique files after dedup
        file_count = sum(1 for f in tmp.rglob("*") if f.is_file())
        if file_count == 0:
            print("→ 指定提交中没有可提取的变更文件")
            sys.exit(0)

        # Package with tarfile
        print(f"→ 打包到 {args.o} ...")
        with tarfile.open(args.o, "w:gz") as tar:
            for f in tmp.rglob("*"):
                if f.is_file():
                    tar.add(f, arcname=f.relative_to(tmp))

        size = Path(args.o).stat().st_size
        print(
            f"✅ 完成！{args.o} ({format_size(size)})"
            f" — {len(sorted_commits)} 个提交，去重后 {file_count} 个文件"
        )


if __name__ == "__main__":
    main()
