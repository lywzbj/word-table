#!/bin/bash
# pack-branch-changes.sh —— Package changed files from current branch (Linux/macOS)
#   Usage: ./pack-branch-changes.sh [-n N] [-o output.tar.gz] [base-branch]
set -euo pipefail

# ---------- Argument parsing ----------
COMMIT_COUNT=""
while getopts "n:o:h" opt; do
    case "$opt" in
        n) COMMIT_COUNT="$OPTARG" ;;
        o) OUTPUT="$OPTARG" ;;
        h) echo "Usage: $0 [-n N] [-o output.tar.gz] [base-branch]" ; exit 0 ;;
        *) echo "Usage: $0 [-n N] [-o output.tar.gz] [base-branch]" ; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

: "${OUTPUT:=branch-changes.tar.gz}"
MAIN_BRANCH="${1:-}"
# -------------------------

# Determine diff base
if [ -n "$COMMIT_COUNT" ]; then
    if ! [[ "$COMMIT_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: -n must be a positive integer"
        exit 1
    fi
    DIFF_BASE="HEAD~${COMMIT_COUNT}"
    if ! git rev-parse --verify "$DIFF_BASE" >/dev/null 2>&1; then
        echo "Error: not enough history for $COMMIT_COUNT commits ($DIFF_BASE does not exist)"
        exit 1
    fi
    echo "→ Packaging changes from last $COMMIT_COUNT commit(s)"
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
            echo "Error: cannot auto-detect main branch, specify manually: $0 -o output.tar.gz main"
            exit 1
        fi
        echo "→ Detected base branch: $MAIN_BRANCH"
    fi

    DIFF_BASE=$(git merge-base HEAD "$MAIN_BRANCH" 2>/dev/null || true)
    if [ -z "$DIFF_BASE" ]; then
        echo "Error: cannot determine merge-base with $MAIN_BRANCH"
        exit 1
    fi
    echo "→ Merge base: $(git rev-parse --short "$DIFF_BASE")"
fi

echo "→ Collecting changed files..."
FILES=$(git diff --name-only --diff-filter=ACMR "$DIFF_BASE" HEAD)

if [ -z "$FILES" ]; then
    echo "→ No changed files"
    exit 0
fi

# Create temp directory for packaging (needed to include generated CHANGELOG.md)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "→ Copying files to staging area..."
while IFS= read -r file; do
    [ -z "$file" ] && continue
    target="$TEMP_DIR/$file"
    mkdir -p "$(dirname "$target")"
    cp -- "$file" "$target"
done <<< "$FILES"

# Build CHANGELOG.md
CHANGELOG="$TEMP_DIR/CHANGELOG.md"
{
    echo "# Change Log"
    echo ""
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '(detached)')"
    echo "Diff base: $(git rev-parse --short "$DIFF_BASE")"
    echo ""
    echo "## Commits ($(git rev-list --count "$DIFF_BASE"..HEAD))"
    echo ""

    git log --format="%H %s" "$DIFF_BASE"..HEAD | while IFS=' ' read -r hash subject; do
        short=$(git rev-parse --short "$hash" 2>/dev/null || echo "${hash:0:7}")
        echo "### $short - ${subject#* }"
        echo ""
        commit_files=$(git diff-tree --no-commit-id -r --name-only --diff-filter=ACMR "$hash")
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

FILE_COUNT=$(find "$TEMP_DIR" -type f | wc -l | tr -d ' ')
SIZE=$(du -h "$OUTPUT" | cut -f1)
echo "Done: $OUTPUT ($SIZE) — $(echo "$FILES" | wc -l | tr -d ' ') file(s)"
