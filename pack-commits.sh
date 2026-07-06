#!/bin/bash
# pack-commits.sh —— Package changed files from specified commits (Linux/macOS)
#   Usage: ./pack-commits.sh [-o output.tar.gz] <commit1> [commit2] [...]
set -euo pipefail

# ---------- Argument parsing ----------
OUTPUT="commits-changes.tar.gz"
COMMITS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) OUTPUT="$2"; shift 2 ;;
        -h) echo "Usage: $0 [-o output.tar.gz] <commit1> [commit2] [...]" ; exit 0 ;;
        -*) echo "Unknown option: $1" ; exit 1 ;;
        *)  COMMITS+=("$1"); shift ;;
    esac
done

if [ ${#COMMITS[@]} -eq 0 ]; then
    echo "Error: at least one commit hash is required"
    echo "Usage: $0 [-o output.tar.gz] <commit1> [commit2] [...]"
    exit 1
fi
# -------------------------

for commit in "${COMMITS[@]}"; do
    if ! git cat-file -e "$commit^{commit}" 2>/dev/null; then
        echo "Error: $commit is not a valid commit"
        exit 1
    fi
done

echo "→ Resolving commits..."
SORTED_COMMITS=()
while IFS= read -r hash; do
    SORTED_COMMITS+=("$hash")
done < <(git rev-list --no-walk --date-order --reverse "${COMMITS[@]}")

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

for commit in "${SORTED_COMMITS[@]}"; do
    SHORT_HASH=$(git rev-parse --short "$commit")
    echo "→ Processing $SHORT_HASH ..."

    while IFS= read -r file; do
        [ -z "$file" ] && continue
        target="$TEMP_DIR/$file"
        mkdir -p "$(dirname "$target")"
        if git show "$commit:$file" > "$target" 2>/dev/null; then
            :  # success
        else
            echo "  Warning: cannot extract $file"
        fi
    done < <(git diff-tree --no-commit-id -r --name-only --diff-filter=ACMR "$commit")
done

FILE_COUNT=$(find "$TEMP_DIR" -type f | wc -l | tr -d ' ')

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "→ No changed files in the specified commits"
    exit 0
fi

# Build CHANGELOG.md in temp dir
CHANGELOG="$TEMP_DIR/CHANGELOG.md"
{
    echo "# Change Log"
    echo ""
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '(detached)')"
    echo ""
    echo "## Commits (${#SORTED_COMMITS[@]})"
    echo ""

    for commit in "${SORTED_COMMITS[@]}"; do
        short=$(git rev-parse --short "$commit")
        subject=$(git log --format=%s -n1 "$commit")
        echo "### $short - $subject"
        echo ""
        commit_files=$(git diff-tree --no-commit-id -r --name-only --diff-filter=ACMR "$commit")
        if [ -n "$commit_files" ]; then
            echo "| File |"
            echo "|------|"
            while IFS= read -r f; do
                [ -z "$f" ] && continue
                echo "| \`$f\` |"
            done <<< "$commit_files"
        else
            echo "*(empty commit)*"
        fi
        echo ""
    done
} > "$CHANGELOG"

echo "→ Packaging to $OUTPUT ..."
tar -czf "$OUTPUT" -C "$TEMP_DIR" .

SIZE=$(du -h "$OUTPUT" | cut -f1)
echo "Done: $OUTPUT ($SIZE) — ${#SORTED_COMMITS[@]} commit(s), $FILE_COUNT unique file(s)"
