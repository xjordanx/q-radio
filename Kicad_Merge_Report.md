# QRadio block merge report

Branch: `variant/rfpp4-div` · Executed 2026-09-10/11 per `Kicad_Merge_Prompt.md`
Tool: `scripts/merge_blocks.py` (KiCad 10.0.5 pcbnew API, headless) · Full run log: `merge-board-run.log`

Commits: `14da67d` phase 1 (schematics + metadata) · `b8e61af` phase 2 (board merge) · `6fd1b2a` zone refill

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

Skipped from blocks by design: 20 rule areas (master keeps its own), 22 In1/In4 GND zones, all Edge.Cuts, graphics, text, dimensions and groups. Zone fills imported as-is, then **all 102 copper zones refilled** headlessly after the merge (stale master fills had overlapped the moved parts).

Net remapping (block-local hierarchical names → master nets, matched by label leaf): **54 mapped**, e.g. `/Power/1V2_EN → /Microcontroller/1V2_EN`, `/Mixer/RX_EN → /IF Transceiver/RX_EN`, `/USB/VBUS → /Power/VBUS` (full list in the run log). **3 created** because master's netlist predates the edited power sheet: `/Power/VRM_IN`, `/Power/VSW_1`, `/Power/VSW_2` — expected to resolve at schematic update.

## 4. DRC snapshot (headless, after refill, BEFORE schematic update)

1398 violations, 230 unconnected. kicad-cli caps each category at 199, so counts of 199 mean "≥199". Interpretation:

- `shorting_items` ≥199 — dominant cause is pads carrying the **old netlist** while imported tracks carry the block netlist (e.g. GND pad vs `/Clock Generator/CLK0` track). Expected to largely vanish after Update PCB from Schematic. A distinct real cluster: `3V3LED ↔ /USB/D+`, `3V3LED ↔ /USB/D-`, `/USB/CC1 ↔ CC2` — the **pre-placed LED-SW block physically overlaps usb block routing**. 23 via↔via overlaps also present.
- `items_not_allowed` ≥199 (all tracks) — master's Quilter placement rule areas still forbid tracks.
- `track_width` ≥199 — tracks at **0.1233 mm** vs master min 0.127 (GND 75, clock nets…). Quilter output; decide whether to accept.
- `clearance` 164, `hole_clearance` 31, `courtyards_overlap` 50, `zones_intersect` 8, `copper_edge_clearance` 18, `tracks_crossing` 14, `pth_inside_courtyard` 9, `via_dangling` 44, `track_dangling` 16, `isolated_copper` 7, `unresolved_variable` 8.
- 230 unconnected = LED-SW block (never routed) + inter-block connections (the purpose of the final routing pass).

## 5. TO-DO — items requiring human attention (in order)

1. **Update PCB from Schematic** (Tools → Update PCB from Schematic, keep "re-link footprints by UUID") — first, before judging anything else. Confirm `/Power/VRM_IN`, `VSW_1`, `VSW_2` bind to pads, and that no footprint is reported as missing/extra (block sheet edits vs master board).
2. Refill zones and re-run DRC after (1); re-triage the shorting list — what remains is real.
3. **Master rule areas**: the Quilter placement regions (≈197 rule areas) forbid tracks → remove them or clear their "keep out tracks/vias" flags now that placement is done.
4. **LED-SW ↔ usb collision**: pre-placed LED-SW parts/tracks overlap usb routing (3V3LED vs D+/D-, CC1/CC2). Move LED-SW or reroute usb's D± locally; also review the 50 courtyard overlaps in that area.
5. **Same-net zone overlaps** (8 `zones_intersect`): block power pours meeting master pours on the same net/layer — merge outlines or assign priorities.
6. **Track width policy**: accept Quilter's 0.1233 mm tracks (lower `min_track_width` to 0.12) or widen — ~200 segments, mostly GND and clock nets.
7. **Block seams**: 23 via↔via overlaps, 14 crossing tracks, 44 dangling vias, 16 dangling tracks — clean during the inter-block routing pass.
8. **Edge clearance** (18) and `pth_inside_courtyard` (9), `hole_clearance` (31): check block routing that ran to the block boundary now sitting at the real board edge, and via-in-pad cases.
9. **GND planes**: no In1.GND.Cu / In4.GND.Cu zones exist in the merged board (block ones dropped per 5.d, master had none) — add full-board GND zones on both layers before the final routing job.
10. **Fab confirmation**: 0.2032 mm (8 mil) via drills from mcu/mixer are now permitted by the board rules — confirm capability.
11. Verify FID1–3 positions (master's kept) and the 8 unresolved text variables (title-block vars from block sheets).
12. Then: commit the schematic-updated board, `quilter-send` from this branch, and submit the inter-block routing job.
