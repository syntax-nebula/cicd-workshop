#!/usr/bin/env bash
set -euo pipefail   # stop at the first failing command (-e), an unset variable (-u), or a failure inside a pipe (pipefail)
PREV=$(git describe --tags --abbrev=0 --match 'v*' HEAD^ 2>/dev/null || git rev-list --max-parents=0 HEAD)   # the previous release tag
CURRENT=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || git rev-parse --short HEAD)

echo "# Deployment record — ${CURRENT}"
echo
echo "- Deployed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "- Commit:   $(git rev-parse HEAD)"
echo "- Range:    ${PREV}..${CURRENT}"
echo
echo "## Changes"
git log "${PREV}..HEAD" --pretty=format:'- %s (%h)' --no-merges
echo
echo
echo "## Breaking changes"
git log "${PREV}..HEAD" --grep='BREAKING CHANGE' --pretty=format:'- %s (%h)' || echo "- none"
echo
echo
echo "## Event schema"
grep -A2 'Current schema version' docs/events.md | head -3
