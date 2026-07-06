#!/bin/bash
# pack-commits.sh —— 提取指定提交的变更文件并打包 (Linux/macOS)
#   用法: ./pack-commits.sh [-o output.tar.gz] <commit1> [commit2] [...]
set -euo pipefail

# ---------- 参数解析 ----------
OUTPUT="commits-changes.tar.gz"
COMMITS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) OUTPUT="$2"; shift 2 ;;
        -h) echo "用法: $0 [-o output.tar.gz] <commit1> [commit2] [...]" ; exit 0 ;;
        -*) echo "未知选项: $1" ; exit 1 ;;
        *)  COMMITS+=("$1"); shift ;;
    esac
done

if [ ${#COMMITS[@]} -eq 0 ]; then
    echo "错误：请至少指定一个提交哈希"
    echo "用法: $0 [-o output.tar.gz] <commit1> [commit2] [...]"
    exit 1
fi
# -------------------------

for commit in "${COMMITS[@]}"; do
    if ! git cat-file -e "$commit^{commit}" 2>/dev/null; then
        echo "错误：$commit 不是有效的提交"
        exit 1
    fi
done

echo "→ 解析提交..."
SORTED_COMMITS=()
while IFS= read -r hash; do
    SORTED_COMMITS+=("$hash")
done < <(git rev-list --no-walk --date-order --reverse "${COMMITS[@]}")

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

for commit in "${SORTED_COMMITS[@]}"; do
    SHORT_HASH=$(git rev-parse --short "$commit")
    echo "→ 处理 $SHORT_HASH ..."

    while IFS= read -r file; do
        [ -z "$file" ] && continue
        target="$TEMP_DIR/$file"
        mkdir -p "$(dirname "$target")"
        if git show "$commit:$file" > "$target" 2>/dev/null; then
            :  # success
        else
            echo "  警告：无法提取 $file"
        fi
    done < <(git diff-tree --no-commit-id -r --name-only --diff-filter=ACMR "$commit")
done

FILE_COUNT=$(find "$TEMP_DIR" -type f | wc -l | tr -d ' ')

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "→ 指定提交中没有可提取的变更文件"
    exit 0
fi

echo "→ 打包到 $OUTPUT ..."
tar -czf "$OUTPUT" -C "$TEMP_DIR" .

SIZE=$(du -h "$OUTPUT" | cut -f1)
echo "✅ 完成！$OUTPUT ($SIZE) — ${#SORTED_COMMITS[@]} 个提交，去重后 $FILE_COUNT 个文件"
