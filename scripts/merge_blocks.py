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
#           - import copper zones (fills retained); skip any zone confined
#             to In1.GND.Cu / In4.GND.Cu
#           - block RULE AREAS replace the master's (KEEP_MASTER_RULE_AREAS
#             are the only master ones retained)
#           - blocks listed in ANCHORS are translated so the anchor ref lands
#             on its master position (for blocks routed in a shifted frame)
#           - cross-block footprint overlap check before saving
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
# Blocks whose candidate frame is shifted relative to the master: translate
# the whole block so this reference lands exactly on its master position.
ANCHORS = {"usb": "J1"}
# Block rule areas OVERRIDE the master's; master keeps only these (no block owns them).
KEEP_MASTER_RULE_AREAS = {"LED_SW", "legend"}
REPORT = []

def log(msg):
    REPORT.append(msg)
    print(msg, flush=True)

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

    net_cache = {}
    def master_net(name):
        name = str(name)
        if name in net_cache:
            return net_cache[name]
        net = master.FindNet(name)
        if net is not None and (net.GetNetCode() != 0 or not name):
            net_cache[name] = net
            return net
        # Block projects name hierarchical nets by THEIR sheet; the master
        # may know the same net under another sheet's prefix. Match by the
        # leaf label when that is unambiguous.
        leaf = name.rsplit("/", 1)[-1]
        cands = [str(n) for n in master.GetNetsByName().keys()
                 if str(n) and str(n).rsplit("/", 1)[-1] == leaf]
        if len(cands) == 1:
            net = master.FindNet(cands[0])
            log("net MAPPED by label: %s -> %s" % (name, cands[0]))
        else:
            ni = pcbnew.NETINFO_ITEM(master, name)
            master.Add(ni)
            net = master.FindNet(name)
            log("net CREATED in master (no unique match%s): %s"
                % (", candidates: " + ", ".join(cands) if cands else "", name))
        net_cache[name] = net
        return net

    totals = {"moved": 0, "tracks": 0, "arcs": 0, "vias": 0, "zones": 0,
              "rule_areas_imported": 0, "zones_skipped_gnd": 0, "missing_ref": []}
    block_refs = {}
    # master rule areas to drop are collected now, removed just before save
    # (removing zones mid-run destabilises subsequent LoadBoard calls).
    master_rule_areas_to_drop = [z for z in master.Zones()
                                 if z.GetIsRuleArea() and str(z.GetZoneName()) not in KEEP_MASTER_RULE_AREAS]
    for b in BLOCKS:
        bp = os.path.join(b, "q-radio.kicad_pcb")
        blk = pcbnew.LoadBoard(bp)
        blk_layers = [blk.GetLayerName(l) for l in blk.GetEnabledLayers().Seq()]
        if blk_layers != master_layers:
            log("ERROR: %s layer table differs from master -- block SKIPPED" % b)
            continue
        # translation for shifted block frames (anchor ref -> master position)
        delta = pcbnew.VECTOR2I(0, 0)
        if b in ANCHORS:
            afp = blk.FindFootprintByReference(ANCHORS[b])
            amf = master.FindFootprintByReference(ANCHORS[b])
            if afp and amf:
                delta = amf.GetPosition() - afp.GetPosition()
                log("%s: translating block by (%.3f, %.3f) mm, anchored on %s"
                    % (b, pcbnew.ToMM(delta.x), pcbnew.ToMM(delta.y), ANCHORS[b]))
            else:
                log("WARNING: %s anchor %s not found; no translation applied" % (b, ANCHORS[b]))
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
            mfp.SetPosition(fp.GetPosition() + delta)
            mfp.SetOrientation(fp.GetOrientation())
            block_refs.setdefault(b, []).append(ref)
            moved += 1
        nt = na = nv = 0
        for t in blk.GetTracks():
            cls = t.GetClass()
            net = master_net(t.GetNetname())
            if cls == "PCB_VIA":
                item = pcbnew.PCB_VIA(master)
                item.SetViaType(t.GetViaType())
                item.SetLayerPair(t.TopLayer(), t.BottomLayer())
                # KiCad 10: via geometry is a per-layer padstack; copy it whole.
                try:
                    item.SetPadstack(t.Padstack())
                except AttributeError:
                    item.SetWidth(t.GetWidth(pcbnew.F_Cu))
                    item.SetDrill(t.GetDrill())
                item.SetPosition(t.GetPosition() + delta)
                nv += 1
            elif cls == "PCB_ARC":
                item = pcbnew.PCB_ARC(master)
                item.SetStart(t.GetStart() + delta)
                item.SetMid(t.GetMid() + delta)
                item.SetEnd(t.GetEnd() + delta)
                item.SetWidth(t.GetWidth())
                item.SetLayer(t.GetLayer())
                na += 1
            else:
                item = pcbnew.PCB_TRACK(master)
                item.SetStart(t.GetStart() + delta)
                item.SetEnd(t.GetEnd() + delta)
                item.SetWidth(t.GetWidth())
                item.SetLayer(t.GetLayer())
                nt += 1
            item.SetNet(net)
            master.Add(item)
        nz = nra = 0
        for z in blk.Zones():
            is_rule = z.GetIsRuleArea()
            if not is_rule:
                znames = layer_names(blk, z.GetLayerSet())
                if znames and znames <= SKIP_ZONE_LAYERS:
                    totals["zones_skipped_gnd"] += 1
                    continue
            try:
                dz = z.Duplicate(False)   # KiCad 10: addToParentGroup
            except TypeError:
                dz = z.Duplicate()
            if hasattr(dz, "Cast"):
                dz = dz.Cast()            # generic BOARD_ITEM -> ZONE
            if delta.x or delta.y:
                dz.Move(delta)
            master.Add(dz)
            if is_rule:
                nra += 1
                totals["rule_areas_imported"] += 1
            else:
                dz.SetNet(master_net(z.GetNetname()))
                nz += 1
        log("%-15s moved:%d tracks:%d arcs:%d vias:%d zones:%d rule-areas:%d" % (b, moved, nt, na, nv, nz, nra))
        totals["moved"] += moved
        totals["tracks"] += nt
        totals["arcs"] += na
        totals["vias"] += nv
        totals["zones"] += nz
    if totals["missing_ref"]:
        log("refs NOT found in master (skipped): %s" % ", ".join(totals["missing_ref"]))
    log("TOTALS: %s" % {k: v for k, v in totals.items() if k != "missing_ref"})
    # Sanity check: footprints of different blocks must not overlap.
    boxes = {}
    for b, refs in block_refs.items():
        for r in refs:
            f = master.FindFootprintByReference(r)
            if f:
                boxes[r] = (b, f.GetBoundingBox())
    pairs = {}
    names = list(boxes)
    for i in range(len(names)):
        bi, boxi = boxes[names[i]]
        for j in range(i + 1, len(names)):
            bj, boxj = boxes[names[j]]
            if bi != bj and boxi.Intersects(boxj):
                pairs.setdefault(tuple(sorted((bi, bj))), []).append("%s/%s" % (names[i], names[j]))
    if pairs:
        for k, v in sorted(pairs.items()):
            log("CROSS-BLOCK OVERLAP %s <> %s: %d footprint pairs, e.g. %s" % (k[0], k[1], len(v), ", ".join(v[:6])))
    else:
        log("cross-block footprint overlap check: none")
    # Block rule areas override the master's: drop master's except the keep-list.
    dropped = []
    for z in master_rule_areas_to_drop:
        dropped.append(str(z.GetZoneName()) or "(unnamed)")
        master.Remove(z)
    log("master rule areas REMOVED (%d): %s" % (len(dropped), ", ".join(dropped)))
    log("master rule areas KEPT: %s" % ", ".join(sorted(KEEP_MASTER_RULE_AREAS)))
    pcbnew.SaveBoard(out_path, master)
    log("saved merged board: %s" % out_path)
    del master_rule_areas_to_drop

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
