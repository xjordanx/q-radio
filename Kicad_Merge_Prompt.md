### QRadio KiCad Merging Instructions

IMPORTANT NOTES:
* ALL submodule candidates have been chosen and downloaded from Quilter.
* All submodule candidates have been identified within each submodule by text file with JobLink URI.
* All submodule candidates have been copied out of zip file into submodule KiCad project and edited.

## Merge Instructions

1. DO NOT COPY .KiCad_Pcb files out of Zip archives - that has already been done.
2. Copy block schematics to parent master KiCad QRadio projeect directory as they have also been modified: Overwrite all block .kicad_sch files.
3. DO NOT OVERWRITE master q-radio.kicad_sch file as it contains necessary top-level wiring. DO NOT OVERWRITE q-radio.kicad_sch!
4. BEFORE MERGE of q-radio.kicad_pcb:
	4.a. Master q-radio.kicad_pcb is an unrouted, placed version of the board with outline and all components and associated placement zones. This MUST be used as the base PCB file for merge.
	4.b. All submodule components and associated placement zones have been removed, ready to merge in those placed and routed from Quilter.
	4.c. Establish a clear and non-destructive plan for merging board meta-data that may be slightly different between the Master and each submodule, particularly Net and Component Classes and associated design rules, pre-defined sizes, and impedance classes. Generally everything should be identical but some special cases have been added to some modules and must be retained.
5. MERGE:  
	5.a. Using the KiCad API, merge in each submodule q-radio.kicad_pcb from the subdirectory it is located in. e.g. .\adc-dac\q-radio.kicad_pcb is the adc-dac submodule. It's content shall be copied into .\q-radio.kicad_pcb (the master file), without it's Edge.Cuts and other non-essential items.
	5.b. The list of submodules to be merged into the master file is as follows:
		- adc-dac
		- clock
		- fpga
		- frontend
		- if-transceiver
		- image-reject
		- mcu
		- mixer
		- power
		- switch-control
		- usb
	5.c. NOTE: The pre-placed LED-SW block and associated components are in the master already and are to be retained. Schematic merge is done by copy and overwrite of all other submodules as in item 2.
	5.d. When merging SUBMODULES, REMOVE zone fills on GND-only layers In1.GND.Cu and In4.GND.Cu. All zone fills on other copper layers must be retained.
6. REPORT: Generate a markdown report detailing the merge work completed, and a to-do list of specific items requiring checking and human attention (for example, recombination of power zone fills on the same net and layer that overlap, etc.)