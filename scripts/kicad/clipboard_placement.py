# clipboard_placement.py -- parse KiCad's clipboard s-expression (what you
# get from Ctrl+C on a selection in the PCB editor) and emit placement.csv
# (ref, x_mm, y_mm, rot_deg, side), same format as
# export_selected_placement.py.
#
# Reads s-expression text on stdin, writes CSV on stdout. Normally you run
# the wrapper instead:   .\scripts\kicad\clipboard-to-placement.ps1
#
# Plain text parsing only -- works with any Python 3, no pcbnew needed.
import csv
import sys


def tokenize(text):
    toks, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in "()":
            toks.append(c); i += 1
        elif c == '"':
            j = i + 1
            buf = []
            while j < n:
                if text[j] == "\\" and j + 1 < n:
                    buf.append(text[j + 1]); j += 2
                elif text[j] == '"':
                    break
                else:
                    buf.append(text[j]); j += 1
            toks.append(("str", "".join(buf))); i = j + 1
        elif c.isspace():
            i += 1
        else:
            j = i
            while j < n and not text[j].isspace() and text[j] not in "()":
                j += 1
            toks.append(("atom", text[i:j])); i = j
    return toks


def parse(toks):
    def walk(idx):
        node = []
        while idx < len(toks):
            t = toks[idx]
            if t == "(":
                child, idx = walk(idx + 1)
                node.append(child)
            elif t == ")":
                return node, idx + 1
            else:
                node.append(t[1]); idx += 1
        return node, idx
    tree, idx = [], 0
    while idx < len(toks):
        if toks[idx] == "(":
            node, idx = walk(idx + 1)
            tree.append(node)
        else:
            idx += 1
    return tree


def find_footprints(node, out):
    if isinstance(node, list):
        if node and node[0] == "footprint":
            out.append(node)
        for child in node:
            find_footprints(child, out)


def extract(fp):
    ref, at, layer = None, None, ""
    for child in fp:
        if not isinstance(child, list) or not child:
            continue
        head = child[0]
        if head == "at" and at is None:  # footprint-level at (first one)
            at = child[1:]
        elif head == "layer" and len(child) > 1:
            layer = child[1]
        elif head == "property" and len(child) > 2 and child[1] == "Reference":
            ref = child[2]
        elif head == "fp_text" and len(child) > 2 and child[1] == "reference":
            ref = ref or child[2]
    if ref is None or at is None:
        return None
    x = float(at[0])
    y = float(at[1])
    rot = float(at[2]) if len(at) > 2 else 0.0
    side = "bottom" if str(layer).startswith("B") else "top"
    return {"ref": ref, "x_mm": x, "y_mm": y, "rot_deg": rot, "side": side}


def main():
    text = sys.stdin.read()
    if "(footprint" not in text:
        sys.stderr.write("clipboard_placement: no footprints found in input. "
                         "Did you Ctrl+C a selection in the PCB editor?\n")
        return 1
    fps = []
    find_footprints(parse(tokenize(text)), fps)
    rows = [r for r in (extract(fp) for fp in fps) if r]
    rows.sort(key=lambda r: r["ref"])
    w = csv.DictWriter(sys.stdout, fieldnames=["ref", "x_mm", "y_mm", "rot_deg", "side"],
                       lineterminator="\n")
    w.writeheader()
    w.writerows(rows)
    sys.stderr.write("clipboard_placement: %d footprints: %s%s\n" % (
        len(rows), ", ".join(r["ref"] for r in rows[:15]),
        " ..." if len(rows) > 15 else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
