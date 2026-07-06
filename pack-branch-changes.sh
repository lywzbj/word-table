#!/bin/bash
# pack-branch-changes.sh —— 提取当前分支变更文件并打包 (Linux/macOS)
#   用法: ./pack-branch-changes.sh [-n N] [output.tar.gz] [base-branch]
set -euo pipefail

# ---------- 参数解析 ----------
 COMMIT_COUNT=""
 while getopts "n:o:h" opt; do
     case "$opt" in
         n) COMMIT_COUNT="$OPTARG" ;;
         o) OUTPUT="$OPTARG" ;;
         h) echo "用法: $0 [-n N] [output.tar.gz] [base-branch]" ; exit 0 ;;
         *) echo "用法: $0 [-n N] [output.tar.gz] [base-branch]" ; exit 1 ;;
     esac
 done
 shift $((OPTIND - 1))
 
 : "${OUTPUT:=branch-changes.tar.gz}"
 MAIN_BRANCH="${1:-}"
# -------------------------

# 确定对比的起点
if [ -n "$COMMIT_COUNT" ]; then
    if ! [[ "$COMMIT_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        echo "错误: -n 后必须是正整数"
        exit 1
    fi
    DIFF_BASE="HEAD~${COMMIT_COUNT}"
    if ! git rev-parse --verify "$DIFF_BASE" >/dev/null 2>&1; then
        echo "错误：仓库历史不足 $COMMIT_COUNT 个提交（$DIFF_BASE 不存在）"
        exit 1
    fi
    echo "→ 提取最近 $COMMIT_COUNT 个提交的变更"
else
    if [ -z "$MAIN_BRANCH" ]; then
        REMOTE_DEFAULT=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}' || true)
        if [ -n "$REMOTE_DEFAULT" ]; then
            MAIN_BRANCH="origin/$REMOTE_DEFAULT"
        elif git show-ref --verify --quiet refs/heads/main; then
            MAIN_BRANCH="main"
        elif git show-ref --verify --quiet refs/heads/master; then
            MAIN_BRANCH="master"
        else
            echo "错误：无法自动检测主分支，请手动指定：$0 output.tar.gz main"
            exit 1
        fi
        echo "→ 检测到主分支: $MAIN_BRANCH"
    fi

    DIFF_BASE=$(git merge-base HEAD "$MAIN_BRANCH" 2>/dev/null || true)
    if [ -z "$DIFF_BASE" ]; then
        echo "错误：无法确定当前分支与 $MAIN_BRANCH 的分叉点"
        exit 1
    fi
    echo "→ 分叉点: $(git rev-parse --short "$DIFF_BASE")"
fi

echo "→ 收集变更文件..."
FILES=$(git diff --name-only --diff-filter=ACMR "$DIFF_BASE" HEAD)

if [ -z "$FILES" ]; then
    echo "→ 没有变更文件"
    exit 0
fi

echo "→ 打包到 $OUTPUT ..."
echo "$FILES" | tar -czf "$OUTPUT" -T -

FILE_COUNT=$(echo "$FILES" | wc -l | tr -d ' ')
SIZE=$(du -h "$OUTPUT" | cut -f1)
echo "✅ 完成！$OUTPUT ($SIZE) — 包含 $FILE_COUNT 个文件"
