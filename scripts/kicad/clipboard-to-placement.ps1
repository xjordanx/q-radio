# clipboard-to-placement.ps1 -- turn a Ctrl+C'd PCB selection into placement.csv
#
# Usage (PowerShell, from the repo folder):
#   1. In the PCB editor: select the footprints you care about, press Ctrl+C
#   2. Run:   .\scripts\kicad\clipboard-to-placement.ps1
#   3. placement.csv appears in the repo root; apply it on the target board
#      with scripts\kicad\apply_placement.py (see that file's header).
#
# Requires any Python 3. Tries PATH first, then KiCad's bundled python.
$ErrorActionPreference = 'Stop'
$repo = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { Write-Error "Run this from inside the repo."; exit 1 }

$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
if (-not $py) {
    $py = Get-ChildItem 'C:\ECAD\KiCad\*\bin\python.exe' -ErrorAction SilentlyContinue |
          Sort-Object FullName | Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $py) { Write-Error "No Python found (PATH or C:\ECAD\KiCad\*\bin)."; exit 1 }

$clip = Get-Clipboard -Raw
if (-not $clip) { Write-Error "Clipboard is empty. Ctrl+C a selection in the PCB editor first."; exit 1 }

$out = Join-Path $repo 'placement.csv'
$clip | & $py (Join-Path $repo 'scripts\kicad\clipboard_placement.py') | Set-Content -Encoding ascii $out
if ($LASTEXITCODE -eq 0) { Write-Host "Wrote $out" } else { exit $LASTEXITCODE }
