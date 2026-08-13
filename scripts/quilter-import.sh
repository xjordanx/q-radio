#!/usr/bin/env bash
# quilter-import.sh -- bring a downloaded Quilter candidate into the project.
#
# Accepts either the ZIP exactly as downloaded from Quilter, or an
# already-unzipped .kicad_pcb. Either way the archive under candidates/
# holds a ZIP: a downloaded zip is MOVED there untouched; a loose board
# file is zipped first (and the loose original removed after success --
# its contents live on in the archive and as the live board).
#
# What it does, in order:
#   1. Validates the input (a zip must contain exactly one .kicad_pcb)
#   2. Creates (or reuses) an experiment branch
#   3. Moves the zip into candidates/<job>/  (never touched again)
#   4. Records it in candidates/manifest.yaml with full traceability
#   5. Installs the board as the live q-radio.kicad_pcb
#   6. Commits everything with the Quilter UUIDs written into the commit
#
# Usage (from the repo folder, in Git Bash / MobaXterm):
#   ./scripts/quilter-import.sh <candidate.zip | candidate.kicad_pcb> -j <job-uuid> [options]
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
  echo "Usage: ./scripts/quilter-import.sh <candidate.zip|candidate.kicad_pcb> -j <job-uuid> [-p project-uuid] [-s q-sent/tag] [-b branch] [-n \"notes\"]"
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

# --- zip helpers: native tools if present, else Windows PowerShell -------
to_native() { command -v cygpath >/dev/null 2>&1 && cygpath -w "$1" || printf '%s' "$1"; }
unzip_to() {  # <zip> <destdir>
  if command -v unzip >/dev/null 2>&1; then unzip -q "$1" -d "$2"
  else powershell.exe -NoProfile -Command \
    "Expand-Archive -LiteralPath '$(to_native "$1")' -DestinationPath '$(to_native "$2")' -Force" >/dev/null
  fi
}
zip_single() {  # <file> <zippath-absolute>
  if command -v zip >/dev/null 2>&1; then (cd "$(dirname "$1")" && zip -q "$2" "$(basename "$1")")
  else powershell.exe -NoProfile -Command \
    "Compress-Archive -LiteralPath '$(to_native "$1")' -DestinationPath '$(to_native "$2")' -Force" >/dev/null
  fi
}

# Default the snapshot tag: prefer the newest q-sent tag REACHABLE from
# the branch you are standing on (tags from parallel experiments on other
# branches are ignored); only if none exists here, fall back to the
# newest tag overall -- loudly, since that may be another experiment's.
if [ -z "$SENT" ]; then
  SENT=$(git tag -l 'q-sent/*' --sort=-creatordate --merged HEAD | head -1)
  if [ -n "$SENT" ]; then
    echo "Using newest snapshot tag on this branch: $SENT"
  else
    SENT=$(git tag -l 'q-sent/*' --sort=-creatordate | head -1)
    if [ -n "$SENT" ]; then
      echo "NOTE: no q-sent tag is reachable from your current branch."
      echo "Falling back to the newest tag overall: $SENT"
      echo "If this job came from a different snapshot, Ctrl+C and rerun with -s <tag>."
    fi
  fi
  [ -n "$SENT" ] && echo "  ($SENT = $(git log -1 --format='%h \"%s\"' "$SENT^{commit}"))"
fi

JOB8="${JOB:0:8}"
BRANCH="${BRANCH:-quilter/$JOB8}"
BASENAME="$(basename "$FILE")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Validate input and settle on: ZIPSRC (zip to archive) + PCBSRC ------
ORIG_LOOSE=""
case "$BASENAME" in
  *.zip|*.ZIP)
    # Extract from a plain-named copy: Quilter names contain [brackets],
    # which some unzip implementations treat as wildcards.
    cp "$FILE" "$TMP/in.zip"
    unzip_to "$TMP/in.zip" "$TMP/x"
    mapfile -t PCBS < <(find "$TMP/x" -type f -name '*.kicad_pcb' | sort)
    if [ "${#PCBS[@]}" -eq 0 ]; then
      echo "ERROR: no .kicad_pcb inside $BASENAME"; exit 1
    elif [ "${#PCBS[@]}" -gt 1 ]; then
      echo "ERROR: $BASENAME contains ${#PCBS[@]} .kicad_pcb files:"
      printf '  %s\n' "${PCBS[@]##*/}"
      echo "Split them into one zip per candidate and import each separately."
      exit 1
    fi
    PCBSRC="${PCBS[0]}"
    ZIPSRC="$FILE"
    ZIPNAME="$BASENAME"
    ;;
  *.kicad_pcb)
    PCBSRC="$FILE"
    ZIPNAME="$BASENAME.zip"
    ZIPSRC="$TMP/$ZIPNAME"
    zip_single "$FILE" "$ZIPSRC"
    ORIG_LOOSE="$FILE"
    ;;
  *)
    echo "ERROR: expected a .zip or .kicad_pcb, got: $BASENAME"; exit 1
    ;;
esac
PCBNAME="$(basename "$PCBSRC")"

# --- Switch to the experiment branch (create it if new) -------------------
BASE="${SENT:-main}"
if git rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then
  git checkout -q "$BRANCH"
  echo "Reusing existing branch: $BRANCH"
else
  git checkout -q -b "$BRANCH" "$BASE"
  echo "Created branch $BRANCH starting from $BASE"
fi

# --- Archive: MOVE the zip into the job directory -------------------------
DEST="candidates/$JOB8/$ZIPNAME"
mkdir -p "candidates/$JOB8"
if [ -e "$DEST" ]; then
  echo "ERROR: $DEST already exists. If this is a different download,"
  echo "rename the file (e.g. candidate_2.zip) and rerun."
  git checkout -q -; exit 1
fi
mv "$ZIPSRC" "$DEST"

if command -v sha256sum >/dev/null; then SHA=$(sha256sum "$DEST" | cut -d' ' -f1)
else SHA=$(shasum -a 256 "$DEST" | cut -d' ' -f1); fi

# --- Record in the manifest ----------------------------------------------
SCHEMATIC_COMMIT=""
[ -n "$SENT" ] && SCHEMATIC_COMMIT=$(git rev-parse --short "$SENT^{commit}")
cat >> candidates/manifest.yaml <<YAML

- quilter_project: "${PROJECT:-unknown}"
  quilter_job: "$JOB"
  file: "$DEST"
  candidate_pcb: "$PCBNAME"
  sha256: "$SHA"
  downloaded: "$(date +%F)"
  sent_tag: "${SENT:-unknown}"
  schematic_commit: "${SCHEMATIC_COMMIT:-unknown}"
  imported_to: "$BRANCH"
  status: "evaluating"
  notes: "${NOTES:-}"
YAML

# --- Make the candidate the live board on this branch --------------------
cp "$PCBSRC" q-radio.kicad_pcb
# The loose original (if any) is fully preserved in the archive + live board.
[ -n "$ORIG_LOOSE" ] && rm -f "$ORIG_LOOSE"

# Stage by directory: bracketed filenames would be treated as glob
# patterns if passed to git add directly.
git add "candidates/$JOB8" candidates/manifest.yaml q-radio.kicad_pcb
git commit -q -m "Import Quilter candidate $PCBNAME (job $JOB8)

Quilter-Project: ${PROJECT:-unknown}
Quilter-Job: $JOB
Quilter-Candidate: $PCBNAME
Quilter-Archive: $ZIPNAME
Source-Snapshot: ${SENT:-unknown}"

echo ""
echo "Imported. You are now on branch: $BRANCH"
echo "The live board q-radio.kicad_pcb IS candidate $PCBNAME."
echo "Archived download: $DEST"
echo ""
echo "NEXT STEPS"
echo "  1. Open q-radio.kicad_pro in KiCad and inspect the board."
echo "  2. Run DRC (Inspect > Design Rules Checker) and note the results:"
echo "     edit candidates/manifest.yaml 'notes:' line, then"
echo "        git add candidates/manifest.yaml && git commit -m \"DRC notes for $JOB8\""
echo "  3. If KiCad asks to save on close, that's fine -- commit the result:"
echo "        git add q-radio.kicad_pcb && git commit -m \"Normalize candidate after opening in KiCad\""
echo "  4. To get back to your main line of work:  git checkout main"
