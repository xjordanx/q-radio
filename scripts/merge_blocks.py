#!/usr/bin/env python
# merge_blocks.py -- merge Quilter-routed block boards into the master q-radio board.
# Run with KiCad's bundled python:
#   C:\ECAD\KiCad\10.0\bin\python.exe scripts\merge_blocks.py --phase meta
#   C:\ECAD\KiCad\10.0\bin\python.exe scripts\merge_blocks.py --phase board --out <path>
#
# Phases:
#   meta  : copy block schematic sheets into the parent project (never
#           q-radio.kicad_sch) and additively merge net classes /
#           pre-defined sizes from block .kicad_pro files into the master.
#   board : merge each block's q-radio.kicad_pcb into the master board:
#           - apply block footprint placements to master footprints (by ref);
#             refs claimed by >1 block keep MASTER position (reported)
#           - import tracks / arcs / vias with nets remapped by name
#           - import copper zones (fills retained); skip rule areas; skip
#             any zone confined to In1.GND.Cu / In4.GND.Cu
#           - never import Edge.Cuts, graphics, text, dimensions, groups
#           Master file is only written via --out (point it at a scratch
#           path to test, at q-radio.kicad_pcb for the real run).
import argparse, json, os, shutil, sys, glob
from collections import OrderedDict

BLOCKS = ["adc-dac", "clock", "fpga", "frontend", "if-transceiver",
          "image-reject", "mcu", "mixer", "power", "switch-control", "usb"]
MASTER_PCB = "q-radio.kicad_pcb"
MASTER_PRO = "q-radio.kicad_pro"
SKIP_ZONE_LAYERS = {"In1.GND.Cu", "In4.GND.Cu"}
REPORT = []

def log(msg):
    REPORT.append(msg)
    print(msg)

# ---------------------------------------------------------------- meta phase
def phase_meta():
    log("## Phase: schematic copy + project metadata merge")
    # 1. copy block sheets into parent (never the top-level q-radio.kicad_sch)
    for b in BLOCKS:
        for src in sorted(glob.glob(os.path.join(b, "*.kicad_sch"))):
            name = os.path.basename(src)
            if name == "q-radio.kicad_sch":
                continue
            shutil.copyfile(src, name)
            log("copied sheet: %s -> ./%s" % (src, name))
    # 2. merge .kicad_pro metadata additively
    with open(MASTER_PRO, "r", encoding="utf-8") as f:
        master = json.load(f, object_pairs_hook=OrderedDict)
    mns = master.setdefault("net_settings", OrderedDict())
    mclasses = mns.setdefault("classes", [])
    mnames = {c.get("name") for c in mclasses}
    mpat = mns.setdefault("netclass_patterns", [])
    mpat_keys = {(p.get("netclass"), p.get("pattern")) for p in mpat}
    mds = master.setdefault("board", OrderedDict()).setdefault("design_settings", OrderedDict())

    for b in BLOCKS:
        ppath = os.path.join(b, "q-radio.kicad_pro")
        if not os.path.isfile(ppath):
            log("NOTE: %s has no .kicad_pro; skipped" % b)
            continue
        with open(ppath, "r", encoding="utf-8") as f:
            blk = json.load(f, object_pairs_hook=OrderedDict)
        bns = blk.get("net_settings", {})
        for c in bns.get("classes", []):
            if c.get("name") not in mnames:
                mclasses.append(c)
                mnames.add(c.get("name"))
                log("net class ADDED from %s: %s" % (b, c.get("name")))
        for p in bns.get("netclass_patterns", []):
            key = (p.get("netclass"), p.get("pattern"))
            if key not in mpat_keys:
                mpat.append(p)
                mpat_keys.add(key)
                log("netclass pattern ADDED from %s: %s -> %s" % (b, p.get("pattern"), p.get("netclass")))
        bds = blk.get("board", {}).get("design_settings", {})
        for lst in ("track_widths", "via_dimensions", "diff_pair_dimensions"):
            bv = bds.get(lst)
            if not bv:
                continue
            mv = mds.setdefault(lst, [])
            for item in bv:
                if item not in mv:
                    mv.append(item)
                    log("pre-defined size ADDED from %s (%s): %s" % (b, lst, item))
        # report (but do not apply) differing scalar rules
        brules, mrules = bds.get("rules", {}), mds.get("rules", {})
        for k, v in brules.items():
            if k in mrules and mrules[k] != v:
                log("RULE DIFFERS (master kept): %s: master=%s %s=%s" % (k, mrules[k], b, v))
    with open(MASTER_PRO, "w", encoding="utf-8") as f:
        json.dump(master, f, indent=2)
        f.write("\n")
    log("master %s updated" % MASTER_PRO)

# --------------------------------------------------------------- board phase
def layer_names(board, layerset):
    return {board.GetLayerName(l) for l in layerset.Seq()}

def phase_board(out_path):
    import pcbnew
    log("## Phase: board merge (pcbnew %s)" % pcbnew.GetBuildVersion())
    master = pcbnew.LoadBoard(MASTER_PCB)
    men = master.GetEnabledLayers()
    master_layers = [master.GetLayerName(l) for l in men.Seq()]

    # refs claimed by more than one block keep master placement
    seen, multi = {}, set()
    import re
    for b in BLOCKS:
        txt = open(os.path.join(b, "q-radio.kicad_pcb"), encoding="utf-8").read()
        for r in re.findall(r'\(property "Reference" "([^"]+)"', txt):
            if r in seen and seen[r] != b:
                multi.add(r)
            seen[r] = b
    if multi:
        log("refs in multiple blocks -- MASTER placement kept: %s" % ", ".join(sorted(multi)))

    def master_net(name):
        net = master.FindNet(name)
        if net is None or net.GetNetCode() == 0 and name:
            existing = master.FindNet(name)
            if existing:
                return existing
            ni = pcbnew.NETINFO_ITEM(master, name)
            master.Add(ni)
            log("net CREATED in master: %s" % name)
            return master.FindNet(name)
        return net

    totals = {"moved": 0, "tracks": 0, "arcs": 0, "vias": 0, "zones": 0,
              "zones_skipped_rule": 0, "zones_skipped_gnd": 0, "missing_ref": []}
    for b in BLOCKS:
        bp = os.path.join(b, "q-radio.kicad_pcb")
        blk = pcbnew.LoadBoard(bp)
        blk_layers = [blk.GetLayerName(l) for l in blk.GetEnabledLayers().Seq()]
        if blk_layers != master_layers:
            log("ERROR: %s layer table differs from master -- block SKIPPED" % b)
            continue
        moved = 0
        for fp in blk.GetFootprints():
            ref = fp.GetReferenceAsString()
            if ref in multi:
                continue
            mfp = master.FindFootprintByReference(ref)
            if mfp is None:
                totals["missing_ref"].append("%s:%s" % (b, ref))
                continue
            if mfp.IsFlipped() != fp.IsFlipped():
                try:
                    mfp.Flip(mfp.GetPosition(), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)
                except (TypeError, AttributeError):
                    mfp.Flip(mfp.GetPosition(), True)
            mfp.SetPosition(fp.GetPosition())
            mfp.SetOrientation(fp.GetOrientation())
            moved += 1
        nt = na = nv = 0
        for t in blk.GetTracks():
            cls = t.GetClass()
            net = master_net(t.GetNetname())
            if cls == "PCB_VIA":
                item = pcbnew.PCB_VIA(master)
                item.SetPosition(t.GetPosition())
                item.SetWidth(t.GetWidth())
                item.SetDrill(t.GetDrill())
                item.SetViaType(t.GetViaType())
                item.SetLayerPair(t.TopLayer(), t.BottomLayer())
                nv += 1
            elif cls == "PCB_ARC":
                item = pcbnew.PCB_ARC(master)
                item.SetStart(t.GetStart())
                item.SetMid(t.GetMid())
                item.SetEnd(t.GetEnd())
                item.SetWidth(t.GetWidth())
                item.SetLayer(t.GetLayer())
                na += 1
            else:
                item = pcbnew.PCB_TRACK(master)
                item.SetStart(t.GetStart())
                item.SetEnd(t.GetEnd())
                item.SetWidth(t.GetWidth())
                item.SetLayer(t.GetLayer())
                nt += 1
            item.SetNet(net)
            master.Add(item)
        nz = 0
        for z in blk.Zones():
            if z.GetIsRuleArea():
                totals["zones_skipped_rule"] += 1
                continue
            znames = layer_names(blk, z.GetLayerSet())
            if znames and znames <= SKIP_ZONE_LAYERS:
                totals["zones_skipped_gnd"] += 1
                continue
            dz = z.Duplicate()
            master.Add(dz)
            dz.SetNet(master_net(z.GetNetname()))
            nz += 1
        log("%-15s moved:%d tracks:%d arcs:%d vias:%d zones:%d" % (b, moved, nt, na, nv, nz))
        totals["moved"] += moved
        totals["tracks"] += nt
        totals["arcs"] += na
        totals["vias"] += nv
        totals["zones"] += nz
    if totals["missing_ref"]:
        log("refs NOT found in master (skipped): %s" % ", ".join(totals["missing_ref"]))
    log("TOTALS: %s" % {k: v for k, v in totals.items() if k != "missing_ref"})
    pcbnew.SaveBoard(out_path, master)
    log("saved merged board: %s" % out_path)

# ---------------------------------------------------------------------- main
if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=["meta", "board"], required=True)
    ap.add_argument("--out", default=None, help="output board path (board phase)")
    ap.add_argument("--log", default=None, help="append report lines to this file")
    a = ap.parse_args()
    os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if a.phase == "meta":
        phase_meta()
    else:
        if not a.out:
            sys.exit("--out required for board phase")
        phase_board(a.out)
    if a.log:
        with open(a.log, "a", encoding="utf-8") as f:
            f.write("\n".join(REPORT) + "\n")
