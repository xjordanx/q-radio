# quilter-import.ps1 -- bring a downloaded Quilter candidate into the project.
# PowerShell twin of quilter-import.sh; behavior is identical:
#   1. Archives the pristine download under candidates/<job>/  (never touched again)
#   2. Records it in candidates/manifest.yaml with full traceability
#   3. Creates (or reuses) an experiment branch
#   4. Copies the candidate over q-radio.kicad_pcb so KiCad opens it as
#      part of the project (correct name, schematics attached)
#   5. Commits everything with the Quilter UUIDs written into the commit
#
# Usage (from the repo folder, in PowerShell):
#   .\scripts\quilter-import.ps1 <downloaded-file> -Job <job-uuid> [options]
#
#   -Job UUID      Quilter JOB uuid (required)          (alias -j)
#   -Project UUID  Quilter PROJECT uuid (recommended)   (alias -p)
#   -Sent TAG      the q-sent/... snapshot tag this job was created from
#                  (default: the most recent q-sent tag) (alias -s)
#   -Branch NAME   experiment branch (default: quilter/<job-first-8>) (alias -b)
#   -Notes TEXT    free-text note stored in the manifest (alias -n)
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$File,
    [Parameter(Mandatory = $true)][Alias('j')][string]$Job,
    [Alias('p')][string]$Project = 'unknown',
    [Alias('s')][string]$Sent = '',
    [Alias('b')][string]$Branch = '',
    [Alias('n')][string]$Notes = ''
)
$ErrorActionPreference = 'Stop'

$top = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { Write-Error "Not inside a git repository."; exit 1 }

if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
    Write-Host "ERROR: file not found: $File"; exit 1
}
$File = (Resolve-Path -LiteralPath $File).Path   # absolute, before we cd
Set-Location $top

if (git status --porcelain) {
    Write-Host "ERROR: You have uncommitted changes. Commit or discard them first"
    Write-Host "so the import lands as one clean, self-contained commit."
    exit 1
}

# Default the snapshot tag to the most recent q-sent/* tag.
if (-not $Sent) {
    $Sent = git tag -l 'q-sent/*' --sort=-creatordate | Select-Object -First 1
    if ($Sent) { Write-Host "Using most recent snapshot tag: $Sent" }
}

$Job8 = $Job.Substring(0, [Math]::Min(8, $Job.Length))
if (-not $Branch) { $Branch = "quilter/$Job8" }
$BaseName = Split-Path -Leaf $File
$Dest = "candidates/$Job8/$BaseName"

# sha256 of the pristine bytes, for the manifest.
$Sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $File).Hash.ToLower()

# --- Switch to the experiment branch (create it if new) -------------------
$Base = if ($Sent) { $Sent } else { 'main' }
git rev-parse -q --verify "refs/heads/$Branch" *> $null
if ($LASTEXITCODE -eq 0) {
    git checkout -q $Branch
    Write-Host "Reusing existing branch: $Branch"
} else {
    git checkout -q -b $Branch $Base
    Write-Host "Created branch $Branch starting from $Base"
}

# --- Archive the pristine copy -------------------------------------------
New-Item -ItemType Directory -Force -Path "candidates/$Job8" | Out-Null
if (Test-Path -LiteralPath $Dest) {
    Write-Host "ERROR: $Dest already exists. If this is a different download,"
    Write-Host "rename the file (e.g. candidate_2.kicad_pcb) and rerun."
    git checkout -q '-'
    exit 1
}
Copy-Item -LiteralPath $File -Destination $Dest

# --- Record in the manifest ----------------------------------------------
$SchematicCommit = 'unknown'
if ($Sent) { $SchematicCommit = git rev-parse --short "$Sent^{commit}" }
if (-not $Sent) { $Sent = 'unknown' }
$Downloaded = Get-Date -Format yyyy-MM-dd

# Append with LF line endings so the ledger stays uniform across shells.
$entry = (@(
    ''
    "- quilter_project: `"$Project`""
    "  quilter_job: `"$Job`""
    "  file: `"$Dest`""
    "  sha256: `"$Sha`""
    "  downloaded: `"$Downloaded`""
    "  sent_tag: `"$Sent`""
    "  schematic_commit: `"$SchematicCommit`""
    "  imported_to: `"$Branch`""
    "  status: `"evaluating`""
    "  notes: `"$Notes`""
    ''
) -join "`n")
[System.IO.File]::AppendAllText((Join-Path $top 'candidates/manifest.yaml'), $entry)

# --- Make the candidate the live board on this branch --------------------
Copy-Item -LiteralPath $Dest -Destination 'q-radio.kicad_pcb'

git add $Dest candidates/manifest.yaml q-radio.kicad_pcb
git commit -q -m "Import Quilter candidate $BaseName (job $Job8)" -m "Quilter-Project: $Project`nQuilter-Job: $Job`nQuilter-Candidate: $BaseName`nSource-Snapshot: $Sent"
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host ""
Write-Host "Imported. You are now on branch: $Branch"
Write-Host "The live board q-radio.kicad_pcb IS this candidate."
Write-Host ""
Write-Host "NEXT STEPS"
Write-Host "  1. Open q-radio.kicad_pro in KiCad and inspect the board."
Write-Host "  2. Run DRC (Inspect > Design Rules Checker) and note the results:"
Write-Host "     edit candidates/manifest.yaml 'notes:' line, then"
Write-Host "        git add candidates/manifest.yaml ; git commit -m `"DRC notes for $Job8`""
Write-Host "  3. If KiCad asks to save on close, that's fine -- commit the result:"
Write-Host "        git add q-radio.kicad_pcb ; git commit -m `"Normalize candidate after opening in KiCad`""
Write-Host "  4. To get back to your main line of work:  git checkout main"
