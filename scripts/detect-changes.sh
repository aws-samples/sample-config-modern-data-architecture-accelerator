#!/usr/bin/env bash
set -euo pipefail

# Detect which deployable config folders have changed, and print one per line.
#
# In GitLab CI, this uses CI environment variables automatically.
# For local testing, pass a base ref as an argument:
#   ./scripts/detect-changes.sh main
#   ./scripts/detect-changes.sh origin/main
#   ./scripts/detect-changes.sh abc123

# Config dirs are any folder containing mdaa.yaml, up to three levels deep, so a top-level
# folder may either be a config itself (lakehouse/mdaa.yaml) or group several related ones
# (s3_replication/mdaa_manages_one_end/mdaa.yaml).
CONFIG_DIRS=$(find . -mindepth 2 -maxdepth 3 -name "mdaa.yaml" -exec dirname {} \; \
  | sed 's|^\./||' \
  | sort -u)

if [ -z "$CONFIG_DIRS" ]; then
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

CHANGED_TOP_LEVEL=$(echo "$DIFF_FILES" | cut -d'/' -f1 | sort -u)

# Matched on the top-level folder rather than on the config folder itself, so a change to files
# a group shares — its README, say — smoke tests every config in the group.
CHANGED_DIRS=$(echo "$CONFIG_DIRS" | while IFS= read -r config_dir; do
  if echo "$CHANGED_TOP_LEVEL" | grep -qxF "${config_dir%%/*}"; then
    echo "$config_dir"
  fi
done)

if [ -z "$CHANGED_DIRS" ]; then
  echo "No relevant config folders changed." >&2
  exit 0
fi

echo "$CHANGED_DIRS"
