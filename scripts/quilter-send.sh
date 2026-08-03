#!/usr/bin/env bash
# quilter-send.sh -- record EXACTLY what you are about to upload to Quilter.
#
# Run this IMMEDIATELY BEFORE uploading the board to Quilter. It puts a
# permanent named marker (a git "tag") on the current saved state of the
# project, so that every candidate Quilter sends back can be traced to the
# exact input that produced it.
#
# Usage (from the repo folder, in Git Bash):
#   ./scripts/quilter-send.sh <short-label>
#   ./scripts/quilter-send.sh floorplan-b
#
# The label is free text for humans: name the experiment you are starting.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

LABEL="${1:-}"
if [ -z "$LABEL" ]; then
  echo "Usage: ./scripts/quilter-send.sh <short-label>   e.g. floorplan-b"
  exit 1
fi

# Refuse to run with unsaved/uncommitted work: the tag must describe
# a state that actually exists in git history.
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: You have uncommitted changes. Commit them first so the"
  echo "snapshot tag points at the true state you are uploading:"
  echo "    git add -A && git commit -m \"describe your change\""
  exit 1
fi

TAG="q-sent/$(date +%F)-${LABEL}"
N=2
while git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; do
  TAG="q-sent/$(date +%F)-${LABEL}-$N"; N=$((N+1))
done

git tag -a "$TAG" -m "Snapshot uploaded to Quilter: $LABEL"

echo ""
echo "Tagged current state as:  $TAG"
echo "  (commit $(git rev-parse --short HEAD), branch $(git branch --show-current))"
echo ""
echo "NEXT STEPS"
echo "  1. Upload q-radio.kicad_pcb (plus whatever Quilter asks for) now."
echo "  2. In the Quilter UI, note the PROJECT UUID and, once you start a"
echo "     run, the JOB UUID."
echo "  3. When you download a candidate, bring it in with:"
echo "     ./scripts/quilter-import.sh <downloaded-file> -j <job-uuid> -s $TAG"
echo "  4. Publish the tag to GitHub too:  git push origin $TAG"
