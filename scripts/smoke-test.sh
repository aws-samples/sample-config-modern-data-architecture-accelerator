#!/usr/bin/env bash
set -euo pipefail

# Run MDAA synth smoke tests for changed folders.
# Reads folder names from stdin, one per line.
# Fails fast
#
# Usage:
#   echo "agentic_app" | ./scripts/smoke-test.sh
#   cat changed_dirs.txt | ./scripts/smoke-test.sh
#   ./scripts/detect-changes.sh main | ./scripts/smoke-test.sh

while IFS= read -r dir; do
  [ -z "$dir" ] && continue

  config="$dir/mdaa.yaml"
  if [ ! -f "$config" ]; then
    echo "ERROR: $config not found. This indicates a bug in the CI/CD pipeline." >&2
    exit 1
  fi

  echo "Smoke testing: $dir"
  if ! output=$(mdaa synth -c "$config" 2>&1); then
    if echo "$output" | grep -q "spawnSync docker ENOENT"; then
      # TODO need to make this pipeline work with docker
      echo "WARNING: $dir synth failed due to missing Docker (asset bundling). Skipping until docker dependency is resolved." >&2
    else
      echo "$output" >&2
      exit 1
    fi
  fi
done
