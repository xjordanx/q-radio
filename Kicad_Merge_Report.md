# QRadio block merge report

Branch: `variant/rfpp4-div` · Executed 2026-09-10/11 per `Kicad_Merge_Prompt.md` · **Revision 2** (re-merge)
Tool: `scripts/merge_blocks.py` (KiCad 10.0.5 pcbnew API, headless) · Full run log: `merge-board-run.log`

Commits: `14da67d` phase 1 (schematics + metadata) · `9261c25` phase 2 re-merge (supersedes `b8e61af`/`6fd1b2a`)

## 0. Revision 2 — what went wrong in the first merge and what changed

The first merge placed the **usb block on top of the FPGA region** and left **clock and switch-control overlapping**. Root causes, from measurement (not assumption):

- **usb**: the block was routed in a frame shifted (60.764, 1.826) mm from the master (J1 and the block outline had been moved before upload; Quilter placed the rest around them). The first merge imported raw coordinates. Fix: the tool now translates configured blocks so an anchor reference lands exactly on its master position (`ANCHORS = {"usb": "J1"}`) — J1 is back at its board-edge position with Quilter's arrangement preserved around it.
- **clock ↔ switch-control**: not a frame problem. The clock block's own `CLOCK` rule area (x 110.7–136.1) is wider than the master's `Clock Generator` region (118.4–136.1) and overlaps the switch-control block's region (84.1–117.9); both Quilter runs placed parts in the shared 7 mm strip. No translation resolves it — see to-do 4.
- **Rule areas**: per Ben's direction, block rule areas now **override** the master's — 17 master rule areas removed, 20 block rule areas imported; master keeps only `LED_SW` and `legend` (no block owns them). This also clears the `items_not_allowed` wall (199 → 1).
- The tool now runs a **cross-block footprint overlap check** before saving, so a misplaced block can never again pass silently.



## 1. Pre-merge findings (deviations from the instructions, resolved from evidence)

| Instruction | Reality on disk | Resolution |
|---|---|---|
| 4.b "submodule components removed from master" | Master holds **all 514 footprints**; every one of the 482 block refs already exists in master | Merge = **apply block placements + import routing**; no footprints copied. Master-only refs (LED-SW block, H1–H8 mounting holes, FID1–3) untouched |
| 5.d remove In1/In4 GND zone fills | Blocks carried 22 zones confined to In1.GND.Cu / In4.GND.Cu; master has none | All 22 skipped (not imported); master remains without In1/In4 planes — see to-do 9 |
| 4.c metadata "generally identical" | adc-dac adds class `Power`; usb adds `diff85` + 4 patterns; mixer adds pattern `Net-(U5-RF1)→RF`; mcu/power/usb add sizes; **mcu & mixer routed with 0.2032 mm via drills vs master min 0.3** | Classes/patterns/sizes merged additively; `min_through_hole_diameter` relaxed 0.3 → **0.2032** to retain the routed modules (confirm with fab, to-do 10) |
| — | FID1, FID2, FID3 present in several blocks | Master positions kept (block copies were alignment aids) |

No `.kicad_dru` files exist in master or any block.

## 2. Phase 1 — schematics and project metadata

Sheets copied from blocks into the parent (top-level `q-radio.kicad_sch` **not** touched; `LED_SW.kicad_sch` exists only in the parent and was not touched):
`adc-dac, clock, fpga, frontend, baseband (from if-transceiver), image_reject, mcu, mixer, power, switch_control, usb`.
Of these, git shows content changes only in **clock, fpga, image_reject, mixer, power, usb** — the other block sheets were byte-identical to the parent's.

`q-radio.kicad_pro` merged additively: net classes `Power`, `diff85`; netclass patterns for `/USB/D±`, `/Microcontroller/USB_DATA.D±` → diff85 and `Net-(U5-RF1)` → RF; pre-defined track widths (0.127, 0.13335, 0.254, 0.381, 0.508, 0.635, 1.27, 2.54), via sizes (0.4064/0.2032, 0.508/0.254, 0.6096/0.3048, 0.8128/0.4064), diff-pair sizes (0.2/0.25, 0.314/0.133). Scalar rules kept at master values except the through-hole relaxation above (mcu/mixer also declare `min_via_diameter` 0.4064 > master 0.4 — harmless, master kept).

## 3. Phase 2 — board merge

| Block | Footprints moved | Tracks | Vias | Copper zones imported |
|---|---|---|---|---|
| adc-dac | 49 | 397 | 56 | 5 |
| clock | 36 | 371 | 54 | 7 |
| fpga | 31 (+3 FID kept) | 283 | 41 | 12 |
| frontend | 69 | 469 | 64 | 8 |
| if-transceiver | 39 | 312 | 54 | 6 |
| image-reject | 21 | 124 | 14 | 1 |
| mcu | 45 | 1418 | 176 | 4 |
| mixer | 77 | 474 | 48 | 4 |
| power | 81 (+3 FID kept) | 306 | 93 | 26 |
| switch-control | 18 | 169 | 25 | 6 |
| usb | 10 | 127 | 13 | 2 |
| **Total** | **476** | **4450** | **638** | **81** |

Skipped from blocks by design: 22 In1/In4 GND zones, all Edge.Cuts, graphics, text, dimensions and groups. Imported: 20 block rule areas (replacing 17 master ones). usb translated by (60.764, 1.826) mm. Zone fills imported as-is, then all copper zones refilled headlessly after the merge.

Cross-block footprint overlaps detected by the tool (bounding-box test, so near-touching pairs are included; courtyard DRC is the authority):

| Blocks | Pairs | Examples |
|---|---|---|
| clock ↔ switch-control | 7 | C119/U26, C120/U26, U19/C24, U19/R96 |
| mcu ↔ power | 8 | P26/C126, P26/L10, P28/C167, R63/C126 |
| frontend ↔ image-reject | 7 | C201 vs L16/L17/L18/C91/C96/C101 |
| fpga ↔ power | 3 | RN4/U32, RN3/C23, RN3/U32 |
| clock ↔ mcu | 2 | D9/P20, P2/P20 |
| adc-dac ↔ clock, adc-dac ↔ if-transceiver, clock ↔ if-transceiver, if-transceiver ↔ switch-control, mcu ↔ usb | 1 each | U36/R105, U35/C92, R41/R149, C86/U39, P20/J1 |

Net remapping (block-local hierarchical names → master nets, matched by label leaf): **54 mapped**, e.g. `/Power/1V2_EN → /Microcontroller/1V2_EN`, `/Mixer/RX_EN → /IF Transceiver/RX_EN`, `/USB/VBUS → /Power/VBUS` (full list in the run log). **3 created** because master's netlist predates the edited power sheet: `/Power/VRM_IN`, `/Power/VSW_1`, `/Power/VSW_2` — expected to resolve at schematic update.

## 4. DRC snapshot (headless, after refill, BEFORE schematic update) — revision 2

1038 violations, 226 unconnected (first merge: 1398 / 230). kicad-cli caps each category at 199, so 199 means "≥199". Interpretation:

- `shorting_items` 163 — dominant cause is pads carrying the **old netlist** while imported tracks carry the block netlist. Expected to largely vanish after Update PCB from Schematic; what remains sits on the block seams listed above.
- `track_width` ≥199 — tracks at **0.1233 mm** vs master min 0.127 (mostly GND and clock nets). Quilter output; decide whether to accept.
- `clearance` 81, `courtyards_overlap` 31, `hole_clearance` 20, `copper_edge_clearance` 18, `tracks_crossing` 15, `zones_intersect` 8, `pth_inside_courtyard` 8, `via_dangling` 43, `track_dangling` 16, `isolated_copper` 7, `unresolved_variable` 8, `items_not_allowed` 1.
- 226 unconnected = LED-SW block (never routed) + inter-block connections (the purpose of the final routing pass).

## 5. TO-DO — items requiring human attention (in order)

1. **Update PCB from Schematic** (Tools → Update PCB from Schematic, keep "re-link footprints by UUID") — first, before judging anything else. Confirm `/Power/VRM_IN`, `VSW_1`, `VSW_2` bind to pads, and that no footprint is reported as missing/extra (block sheet edits vs master board).
2. Refill zones and re-run DRC after (1); re-triage the shorting list — what remains is real.
3. **Rule areas**: block rule areas now define the regions (master's replaced). One `items_not_allowed` remains — check which imported area still forbids that item, and decide whether the imported placement rule areas should be deleted outright now that placement is final.
4. **Block region conflicts** (table in §3): clock ↔ switch-control (the `CLOCK` block region overlaps `/Switch Control/` by ~7 mm; both placed parts there), mcu ↔ power (P26/P28 headers vs power's C126/L10/C167), frontend ↔ image-reject (C201 vs the filter inductors/caps), fpga ↔ power (RN3/RN4 vs U32). Resolve by nudging parts locally or re-running one block with a corrected region; the 31 courtyard overlaps are the DRC view of the same conflicts.
5. **Same-net zone overlaps** (8 `zones_intersect`): block power pours meeting master pours on the same net/layer — merge outlines or assign priorities.
6. **Track width policy**: accept Quilter's 0.1233 mm tracks (lower `min_track_width` to 0.12) or widen — ~200 segments, mostly GND and clock nets.
7. **Block seams**: 23 via↔via overlaps, 14 crossing tracks, 44 dangling vias, 16 dangling tracks — clean during the inter-block routing pass.
8. **Edge clearance** (18) and `pth_inside_courtyard` (9), `hole_clearance` (31): check block routing that ran to the block boundary now sitting at the real board edge, and via-in-pad cases.
9. **GND planes**: no In1.GND.Cu / In4.GND.Cu zones exist in the merged board (block ones dropped per 5.d, master had none) — add full-board GND zones on both layers before the final routing job.
10. **Fab confirmation**: 0.2032 mm (8 mil) via drills from mcu/mixer are now permitted by the board rules — confirm capability.
11. Verify FID1–3 positions (master's kept) and the 8 unresolved text variables (title-block vars from block sheets).
12. Then: commit the schematic-updated board, `quilter-send` from this branch, and submit the inter-block routing job.
