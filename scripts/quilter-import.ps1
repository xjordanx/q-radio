# quilter-import.ps1 -- bring a downloaded Quilter candidate into the project.
# PowerShell twin of quilter-import.sh; behavior is identical.
#
# Accepts either the ZIP exactly as downloaded from Quilter, or an
# already-unzipped .kicad_pcb. Either way the archive under candidates/
# holds a ZIP: a downloaded zip is MOVED there untouched; a loose board
# file is zipped first (and the loose original removed after success --
# its contents live on in the archive and as the live board).
#
# Usage (from the repo folder, in PowerShell):
#   .\scripts\quilter-import.ps1 <candidate.zip|candidate.kicad_pcb> -Job <job-uuid> [options]
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

if (git status --porcelain --untracked-files=no) {
    Write-Host "ERROR: You have uncommitted changes. Commit or discard them first"
    Write-Host "so the import lands as one clean, self-contained commit."
    exit 1
}

# Default the snapshot tag: prefer the newest q-sent tag REACHABLE from
# the branch you are standing on (tags from parallel experiments on other
# branches are ignored); only if none exists here, fall back to the
# newest tag overall -- loudly, since that may be another experiment's.
if (-not $Sent) {
    $Sent = git tag -l 'q-sent/*' --sort=-creatordate --merged HEAD | Select-Object -First 1
    if ($Sent) {
        Write-Host "Using newest snapshot tag on this branch: $Sent"
    } else {
        Write-Host "ERROR: no q-sent tag is reachable from your current branch, so the"
        Write-Host "snapshot this job came from cannot be determined safely."
        Write-Host ""
        Write-Host "Either switch to the branch you uploaded from, or (if you forgot"
        Write-Host "quilter-send before uploading) tag the uploaded commit now:"
        Write-Host '    git tag -a q-sent/<date>-<label> <commit> -m "retroactive"'
        Write-Host "then rerun, or pass the tag explicitly with -Sent <tag>."
        Write-Host ""
        Write-Host "Existing snapshot tags (newest first):"
        git tag -l 'q-sent/*' --sort=-creatordate | Select-Object -First 5 | ForEach-Object { Write-Host "    $_" }
        exit 1
    }
    if ($Sent) { Write-Host "  ($Sent = $(git log -1 --format='%h \"%s\"' "$Sent^{commit}"))" }
}

$Job8 = $Job.Substring(0, [Math]::Min(8, $Job.Length))
if (-not $Branch) { $Branch = "quilter/$Job8" }
$BaseName = Split-Path -Leaf $File
$Tmp = Join-Path $env:TEMP ("qimport-" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force $Tmp | Out-Null

try {
    # --- Validate input; settle on $ZipSrc (zip to archive) + $PcbSrc ----
    $OrigLoose = $null
    if ($BaseName -match '\.zip$') {
        # Extract from a plain-named copy: Quilter names contain [brackets],
        # which trip wildcard handling in some tools.
        Copy-Item -LiteralPath $File -Destination (Join-Path $Tmp 'in.zip')
        Expand-Archive -LiteralPath (Join-Path $Tmp 'in.zip') -DestinationPath (Join-Path $Tmp 'x') -Force
        $pcbs = @(Get-ChildItem -Recurse -File (Join-Path $Tmp 'x') -Filter *.kicad_pcb | Sort-Object Name)
        if ($pcbs.Count -eq 0) { Write-Host "ERROR: no .kicad_pcb inside $BaseName"; exit 1 }
        if ($pcbs.Count -gt 1) {
            Write-Host "ERROR: $BaseName contains $($pcbs.Count) .kicad_pcb files:"
            $pcbs | ForEach-Object { Write-Host "  $($_.Name)" }
            Write-Host "Split them into one zip per candidate and import each separately."
            exit 1
        }
        $PcbSrc = $pcbs[0].FullName
        $ZipSrc = $File
        $ZipName = $BaseName
    }
    elseif ($BaseName -match '\.kicad_pcb$') {
        $PcbSrc = $File
        $ZipName = "$BaseName.zip"
        $ZipSrc = Join-Path $Tmp $ZipName
        Compress-Archive -LiteralPath $File -DestinationPath $ZipSrc -Force
        $OrigLoose = $File
    }
    else {
        Write-Host "ERROR: expected a .zip or .kicad_pcb, got: $BaseName"; exit 1
    }
    $PcbName = Split-Path -Leaf $PcbSrc

    # --- Switch to the experiment branch (create it if new) --------------
    $Base = if ($Sent) { $Sent } else { 'main' }
    git rev-parse -q --verify "refs/heads/$Branch" *> $null
    if ($LASTEXITCODE -eq 0) {
        git checkout -q $Branch
        Write-Host "Reusing existing branch: $Branch"
    } else {
        git checkout -q -b $Branch $Base
        Write-Host "Created branch $Branch starting from $Base"
    }

    # --- Archive: MOVE the zip into the job directory --------------------
    $Dest = "candidates/$Job8/$ZipName"
    New-Item -ItemType Directory -Force -Path "candidates/$Job8" | Out-Null
    if (Test-Path -LiteralPath $Dest) {
        Write-Host "ERROR: $Dest already exists. If this is a different download,"
        Write-Host "rename the file (e.g. candidate_2.zip) and rerun."
        git checkout -q '-'
        exit 1
    }
    Move-Item -LiteralPath $ZipSrc -Destination $Dest

    $Sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Dest).Hash.ToLower()

    # --- Record in the manifest ------------------------------------------
    $SchematicCommit = 'unknown'
    if ($Sent) { $SchematicCommit = git rev-parse --short "$Sent^{commit}" }
    if (-not $Sent) { $Sent = 'unknown' }
    $Downloaded = Get-Date -Format yyyy-MM-dd
    $entry = (@(
        ''
        "- quilter_project: `"$Project`""
        "  quilter_job: `"$Job`""
        "  file: `"$Dest`""
        "  candidate_pcb: `"$PcbName`""
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

    # --- Make the candidate the live board on this branch ----------------
    Copy-Item -LiteralPath $PcbSrc -Destination 'q-radio.kicad_pcb'
    # The loose original (if any) is preserved in the archive + live board.
    if ($OrigLoose) { Remove-Item -LiteralPath $OrigLoose }

    # Stage by directory: bracketed filenames would be treated as glob
    # patterns if passed to git add directly.
    git add "candidates/$Job8" candidates/manifest.yaml q-radio.kicad_pcb
    git commit -q -m "Import Quilter candidate $PcbName (job $Job8)" -m "Quilter-Project: $Project`nQuilter-Job: $Job`nQuilter-Candidate: $PcbName`nQuilter-Archive: $ZipName`nSource-Snapshot: $Sent"
    if ($LASTEXITCODE -ne 0) { exit 1 }

    Write-Host ""
    Write-Host "Imported. You are now on branch: $Branch"
    Write-Host "The live board q-radio.kicad_pcb IS candidate $PcbName."
    Write-Host "Archived download: $Dest"
    Write-Host ""
    Write-Host "NEXT STEPS"
    Write-Host "  1. Open q-radio.kicad_pro in KiCad and inspect the board."
    Write-Host "  2. Run DRC (Inspect > Design Rules Checker) and note the results:"
    Write-Host "     edit candidates/manifest.yaml 'notes:' line, then"
    Write-Host "        git add candidates/manifest.yaml ; git commit -m `"DRC notes for $Job8`""
    Write-Host "  3. If KiCad asks to save on close, that's fine -- commit the result:"
    Write-Host "        git add q-radio.kicad_pcb ; git commit -m `"Normalize candidate after opening in KiCad`""
    Write-Host "  4. To get back to your main line of work:  git checkout main"
}
finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
