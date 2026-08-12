# apply_placement.py -- read placement.csv (written by
# export_selected_placement.py) and move the matching footprints of the
# CURRENTLY OPEN board to those X/Y/rotation/side values.
#
# HOW TO RUN (inside the PCB editor, with the TARGET board open):
#   Tools > Scripting Console, then paste:
#     exec(open(r'C:\ECAD\Designs\QRadio\scripts\kicad\apply_placement.py').read())
#
#   By default it reads placement.csv from the board's own folder. To use
#   a different file, set PLACEMENT_CSV before the exec line:
#     PLACEMENT_CSV = r'C:\somewhere\else\placement.csv'
#
# Matching is by reference designator (safe between variants of the same
# design). Footprints in the CSV that don't exist on this board are
# reported and skipped. Nothing is saved to disk -- inspect the result,
# then File > Save yourself (and commit).
import csv
import os
import pcbnew

board = pcbnew.GetBoard()
try:
    csv_path = PLACEMENT_CSV  # noqa: F821 -- optional user override
except NameError:
    csv_path = os.path.join(os.path.dirname(board.GetFileName()), "placement.csv")

if not os.path.isfile(csv_path):
    print("apply_placement: CSV not found: %s" % csv_path)
else:
    by_ref = {fp.GetReference(): fp for fp in board.GetFootprints()}
    moved, missing = [], []
    with open(csv_path, newline="") as f:
        for row in csv.DictReader(f):
            ref = row["ref"].strip()
            fp = by_ref.get(ref)
            if fp is None:
                missing.append(ref)
                continue
            want_bottom = row["side"].strip().lower() == "bottom"
            if fp.IsFlipped() != want_bottom:
                # Flip API changed across KiCad versions; try new then old.
                try:
                    fp.Flip(fp.GetPosition(), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)
                except (TypeError, AttributeError):
                    fp.Flip(fp.GetPosition(), True)
            fp.SetPosition(pcbnew.VECTOR2I(
                pcbnew.FromMM(float(row["x_mm"])),
                pcbnew.FromMM(float(row["y_mm"])),
            ))
            fp.SetOrientationDegrees(float(row["rot_deg"]))
            moved.append(ref)
    pcbnew.Refresh()
    print("apply_placement: moved %d footprints from %s" % (len(moved), csv_path))
    if missing:
        print("  NOT on this board (skipped): " + ", ".join(missing))
    print("  Review the board, then File > Save and commit.")
