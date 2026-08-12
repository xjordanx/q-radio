# export_selected_placement.py -- write X/Y/rotation/side of the SELECTED
# footprints to a CSV, for transferring partial placement between boards
# that share reference designators (variants of the same design).
#
# Standalone: works in ANY KiCad project. Keep a copy in your KiCad
# scripting folder (C:\ECAD\KiCad\10.0\share\kicad\scripting\) so it is always
# at the same path regardless of which project or git branch is open.
#
# HOW TO RUN (inside the PCB editor):
#   1. Select the footprints you want to capture (click/drag/Ctrl+click).
#   2. Tools > Scripting Console, then paste (adjust path to your copy):
#        exec(open(r'C:\ECAD\KiCad\10.0\share\kicad\scripting\export_selected_placement.py').read())
#   3. The CSV is written next to the board file (placement.csv) and the
#      path + count are printed in the console.
#
# CSV columns: ref, x_mm, y_mm, rot_deg, side
# Coordinates are board-absolute (KiCad's native origin), so applying to a
# variant of the SAME board outline reproduces positions exactly.
import csv
import os
import pcbnew

board = pcbnew.GetBoard()
out_path = os.path.join(os.path.dirname(board.GetFileName()), "placement.csv")

rows = []
for fp in board.GetFootprints():
    if not fp.IsSelected():
        continue
    pos = fp.GetPosition()
    rows.append({
        "ref": fp.GetReference(),
        "x_mm": round(pcbnew.ToMM(pos.x), 6),
        "y_mm": round(pcbnew.ToMM(pos.y), 6),
        "rot_deg": round(fp.GetOrientationDegrees(), 3),
        "side": "bottom" if fp.IsFlipped() else "top",
    })

if not rows:
    print("export_selected_placement: NOTHING SELECTED -- select footprints first.")
else:
    rows.sort(key=lambda r: r["ref"])
    with open(out_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["ref", "x_mm", "y_mm", "rot_deg", "side"])
        w.writeheader()
        w.writerows(rows)
    print("export_selected_placement: wrote %d footprints to %s" % (len(rows), out_path))
    print("  " + ", ".join(r["ref"] for r in rows[:20]) + (" ..." if len(rows) > 20 else ""))
