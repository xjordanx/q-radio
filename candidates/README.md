# candidates/ -- pristine Quilter downloads (KiCad never opens these)

Every board file downloaded from Quilter is archived here EXACTLY as
downloaded, under a folder named after the first 8 characters of the
Quilter job UUID:

    candidates/
      manifest.yaml          <- the ledger: one entry per candidate
      3fa85f64/              <- job UUID (short form)
        candidate_1.kicad_pcb
        candidate_2.kicad_pcb
      9b2c11d0/
        candidate_1.kicad_pcb

Rules:
1. NEVER open these files in KiCad. They are evidence, not working files.
   To work with one, import it onto a branch with scripts/quilter-import.sh,
   which copies it over q-radio.kicad_pcb where KiCad can open it properly.
2. NEVER edit or delete anything here. The whole point is that any board
   state in the project can be traced back to the exact bytes Quilter
   produced.
3. Every file here must have a matching entry in manifest.yaml.
   The scripts maintain this for you.
