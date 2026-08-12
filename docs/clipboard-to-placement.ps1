# clipboard-to-placement.ps1 -- turn a Ctrl+C'd PCB selection into placement.csv
#
# Standalone: works for ANY KiCad project, no git required. Keep a copy
# next to clipboard_placement.py (C:\ECAD\KiCad\10.0\share\kicad\scripting\).
#
# Usage (PowerShell, from any folder -- the CSV lands in the CURRENT folder):
#   1. In the PCB editor: select the footprints you care about, press Ctrl+C
#   2. Run:   <path-to>\clipboard-to-placement.ps1
#   3. placement.csv appears in the current folder; apply it on the target
#      board with apply_placement.py (see that file's header).
#
# Requires any Python 3. Tries PATH first, then KiCad's bundled python.
$ErrorActionPreference = 'Stop'

# The parser lives next to this wrapper, wherever you installed them.
$parser = Join-Path $PSScriptRoot 'clipboard_placement.py'
if (-not (Test-Path $parser)) { Write-Error "clipboard_placement.py not found next to this script ($PSScriptRoot)."; exit 1 }

$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = (Get-Command python3 -ErrorAction SilentlyContinue).Source }
if (-not $py) {
    $py = Get-ChildItem 'C:\ECAD\KiCad\*\bin\python.exe', 'C:\Program Files\KiCad\*\bin\python.exe' -ErrorAction SilentlyContinue |
          Sort-Object FullName | Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $py) { Write-Error "No Python found (PATH, C:\ECAD\KiCad, or Program Files)."; exit 1 }

$clip = Get-Clipboard -Raw
if (-not $clip) { Write-Error "Clipboard is empty. Ctrl+C a selection in the PCB editor first."; exit 1 }

$out = Join-Path (Get-Location) 'placement.csv'
$clip | & $py $parser | Set-Content -Encoding ascii $out
if ($LASTEXITCODE -eq 0) { Write-Host "Wrote $out" } else { exit $LASTEXITCODE }
