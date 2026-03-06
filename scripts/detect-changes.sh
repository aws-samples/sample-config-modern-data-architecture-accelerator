#!/usr/bin/env bash
set -euo pipefail

# Detect which top-level project folders have changed.
#
# In GitLab CI, this uses CI environment variables automatically.
# For local testing, pass a base ref as an argument:
#   ./scripts/detect-changes.sh main
#   ./scripts/detect-changes.sh origin/main
#   ./scripts/detect-changes.sh abc123

# Valid dirs are any top-level folder containing mdaa.yaml
VALID_DIRS=$(find . -maxdepth 2 -name "mdaa.yaml" -exec dirname {} \; \
  | sed 's|^\./||' \
  | cut -d'/' -f1 \
  | sort -u)

if [ -z "$VALID_DIRS" ]; then
  echo "No directories containing mdaa.yaml found." >&2
  exit 0
fi

resolve_base_ref() {
  # Explicit argument takes priority (local usage)
  if [ -n "${1:-}" ]; then
    echo "$1"
    return
  fi

  # MR pipeline — diff against target branch
  if [ -n "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}" ]; then
    git fetch origin "$CI_MERGE_REQUEST_TARGET_BRANCH_NAME" --depth=1 >/dev/null 2>&1
    echo "origin/$CI_MERGE_REQUEST_TARGET_BRANCH_NAME"
    return
  fi

  # Fallback — diff against default branch
  default_branch="${CI_DEFAULT_BRANCH:-main}"
  git fetch origin "$default_branch" --depth=1 >/dev/null 2>&1
  echo "origin/$default_branch"
}

BASE_REF=$(resolve_base_ref "${1:-}")

DIFF_FILES=$(git diff --name-only "$BASE_REF" HEAD)

if [ -z "$DIFF_FILES" ]; then
  echo "No files changed." >&2
  exit 0
fi

CHANGED_DIRS=$(echo "$DIFF_FILES" \
  | cut -d'/' -f1 \
  | sort -u \
  | grep -xF "$VALID_DIRS" \
  || true)

if [ -z "$CHANGED_DIRS" ]; then
  echo "No relevant top-level folders changed." >&2
  exit 0
fi

echo "$CHANGED_DIRS"
