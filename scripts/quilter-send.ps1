# quilter-send.ps1 -- record EXACTLY what you are about to upload to Quilter.
# PowerShell twin of quilter-send.sh; behavior is identical.
#
# Usage (from the repo folder, in PowerShell):
#   .\scripts\quilter-send.ps1 <short-label>
#   .\scripts\quilter-send.ps1 floorplan-b
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Label
)
$ErrorActionPreference = 'Stop'

$top = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { Write-Error "Not inside a git repository."; exit 1 }
Set-Location $top

# Refuse to run with uncommitted work: the tag must describe a state that
# actually exists in git history.
if (git status --porcelain) {
    Write-Host "ERROR: You have uncommitted changes. Commit them first so the"
    Write-Host "snapshot tag points at the true state you are uploading:"
    Write-Host '    git add -A ; git commit -m "describe your change"'
    exit 1
}

$Tag = "q-sent/$(Get-Date -Format yyyy-MM-dd)-$Label"
$n = 2
while ($true) {
    git rev-parse -q --verify "refs/tags/$Tag" *> $null
    if ($LASTEXITCODE -ne 0) { break }
    $Tag = "q-sent/$(Get-Date -Format yyyy-MM-dd)-$Label-$n"
    $n++
}

git tag -a $Tag -m "Snapshot uploaded to Quilter: $Label"
if ($LASTEXITCODE -ne 0) { exit 1 }

$commit = git rev-parse --short HEAD
$branch = git branch --show-current
Write-Host ""
Write-Host "Tagged current state as:  $Tag"
Write-Host "  (commit $commit, branch $branch)"
Write-Host ""
Write-Host "NEXT STEPS"
Write-Host "  1. Upload q-radio.kicad_pcb (plus whatever Quilter asks for) now."
Write-Host "  2. In the Quilter UI, note the PROJECT UUID and, once you start a"
Write-Host "     run, the JOB UUID."
Write-Host "  3. When you download a candidate, bring it in with:"
Write-Host "     .\scripts\quilter-import.ps1 <downloaded-file> -Job <job-uuid> -Sent $Tag"
Write-Host "  4. Publish the tag to GitHub too:  git push origin $Tag"
