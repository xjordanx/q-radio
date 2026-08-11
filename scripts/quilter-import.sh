#!/usr/bin/env bash
# quilter-import.sh -- bring a downloaded Quilter candidate into the project.
#
# What it does, in order:
#   1. Archives the pristine download under candidates/<job>/  (never touched again)
#   2. Records it in candidates/manifest.yaml with full traceability
#   3. Creates (or reuses) an experiment branch
#   4. Copies the candidate over q-radio.kicad_pcb so KiCad opens it as
#      part of the project (correct name, schematics attached)
#   5. Commits everything with the Quilter UUIDs written into the commit
#
# Usage (from the repo folder, in Git Bash):
#   ./scripts/quilter-import.sh <downloaded-file> -j <job-uuid> [options]
#
#   -j UUID   Quilter JOB uuid (required)
#   -p UUID   Quilter PROJECT uuid (optional but recommended)
#   -s TAG    the q-sent/... snapshot tag this job was created from
#             (default: the most recent q-sent tag)
#   -b NAME   experiment branch to import onto (default: quilter/<job-first-8>)
#   -n TEXT   free-text note stored in the manifest
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

FILE="${1:-}"; shift || true
JOB="" PROJECT="" SENT="" BRANCH="" NOTES=""
while getopts "j:p:s:b:n:" opt; do
  case $opt in
    j) JOB="$OPTARG";; p) PROJECT="$OPTARG";; s) SENT="$OPTARG";;
    b) BRANCH="$OPTARG";; n) NOTES="$OPTARG";;
    *) exit 1;;
  esac
done

if [ -z "$FILE" ] || [ -z "$JOB" ]; then
  echo "Usage: ./scripts/quilter-import.sh <downloaded-file> -j <job-uuid> [-p project-uuid] [-s q-sent/tag] [-b branch] [-n \"notes\"]"
  exit 1
fi
if [ ! -f "$FILE" ]; then
  echo "ERROR: file not found: $FILE"; exit 1
fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "ERROR: You have uncommitted changes. Commit or discard them first"
  echo "so the import lands as one clean, self-contained commit."
  exit 1
fi

# Default the snapshot tag to the most recent q-sent/* tag.
if [ -z "$SENT" ]; then
  SENT=$(git tag -l 'q-sent/*' --sort=-creatordate | head -1)
  [ -n "$SENT" ] && echo "Using most recent snapshot tag: $SENT"
fi

JOB8="${JOB:0:8}"
BRANCH="${BRANCH:-quilter/$JOB8}"
BASENAME="$(basename "$FILE")"
DEST="candidates/$JOB8/$BASENAME"

# sha256 of the pristine bytes, for the manifest.
if command -v sha256sum >/dev/null; then SHA=$(sha256sum "$FILE" | cut -d' ' -f1)
else SHA=$(shasum -a 256 "$FILE" | cut -d' ' -f1); fi

# --- Switch to the experiment branch (create it if new) -------------------
BASE="${SENT:-main}"
if git rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then
  git checkout -q "$BRANCH"
  echo "Reusing existing branch: $BRANCH"
else
  git checkout -q -b "$BRANCH" "$BASE"
  echo "Created branch $BRANCH starting from $BASE"
fi

# --- Archive the pristine copy -------------------------------------------
mkdir -p "candidates/$JOB8"
if [ -e "$DEST" ]; then
  echo "ERROR: $DEST already exists. If this is a different download,"
  echo "rename the file (e.g. candidate_2.kicad_pcb) and rerun."
  git checkout -q -; exit 1
fi
cp "$FILE" "$DEST"

# --- Record in the manifest ----------------------------------------------
SCHEMATIC_COMMIT=""
[ -n "$SENT" ] && SCHEMATIC_COMMIT=$(git rev-parse --short "$SENT^{commit}")
cat >> candidates/manifest.yaml <<YAML

- quilter_project: "${PROJECT:-unknown}"
  quilter_job: "$JOB"
  file: "$DEST"
  sha256: "$SHA"
  downloaded: "$(date +%F)"
  sent_tag: "${SENT:-unknown}"
  schematic_commit: "${SCHEMATIC_COMMIT:-unknown}"
  imported_to: "$BRANCH"
  status: "evaluating"
  notes: "${NOTES:-}"
YAML

# --- Make the candidate the live board on this branch --------------------
cp "$DEST" q-radio.kicad_pcb

git add "$DEST" candidates/manifest.yaml q-radio.kicad_pcb
git commit -q -m "Import Quilter candidate $BASENAME (job $JOB8)

Quilter-Project: ${PROJECT:-unknown}
Quilter-Job: $JOB
Quilter-Candidate: $BASENAME
Source-Snapshot: ${SENT:-unknown}"

echo ""
echo "Imported. You are now on branch: $BRANCH"
echo "The live board q-radio.kicad_pcb IS this candidate."
echo ""
echo "NEXT STEPS"
echo "  1. Open q-radio.kicad_pro in KiCad and inspect the board."
echo "  2. Run DRC (Inspect > Design Rules Checker) and note the results:"
echo "     edit candidates/manifest.yaml 'notes:' line, then"
echo "        git add candidates/manifest.yaml && git commit -m \"DRC notes for $JOB8\""
echo "  3. If KiCad asks to save on close, that's fine -- commit the result:"
echo "        git add q-radio.kicad_pcb && git commit -m \"Normalize candidate after opening in KiCad\""
echo "  4. To get back to your main line of work:  git checkout main"
