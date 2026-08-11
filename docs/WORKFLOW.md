# Q-Radio + Quilter workflow guide

This guide assumes **no prior git experience**. It explains how this
repository is organized, and walks through the four flows you will use:
sending a snapshot to Quilter, starting an experiment branch, importing a
downloaded candidate, and picking a winner. All commands are typed into
**Git Bash** (right-click in the project folder → "Open Git Bash here",
or use the Git Bash app and `cd` to the folder) — or into **PowerShell**,
where the two helper scripts have identical `.ps1` twins
(`.\scripts\quilter-send.ps1 <label>`, `.\scripts\quilter-import.ps1
<file> -Job <uuid>`); every plain `git ...` command is the same in both.

A note on line endings: `.gitattributes` pins `*.sh` to LF endings. If a
shell script ever fails with a scrambled error like
`set: pipefail\r: invalid option`, the file has Windows (CRLF) endings —
fix it with `git checkout -- scripts/` after making sure this repo's
`.gitattributes` is present.

---

## 1. The mental model

Git is a **photo album for your whole project folder**.

* A **commit** is one photo: the exact state of every file at one moment,
  plus a message saying what changed and why. Photos are never deleted or
  altered — new ones are only added.
* A **branch** is a named *timeline* of photos. You can have several
  timelines running in parallel — that is how we keep multiple Quilter
  experiments alive at once without them overwriting each other.
* A **tag** is a permanent sticky note on one photo ("this is exactly what
  I uploaded to Quilter on Aug 3").
* **Checking out** a branch makes your folder *become* the latest photo of
  that timeline. The files on disk physically change. This is the trick
  that solves KiCad's naming rule: the board is *always* named
  `q-radio.kicad_pcb`, and *which* board that is depends only on which
  branch you are standing on.

```
                 (each o is a commit -- one snapshot of the whole folder)

   main:         o───o───o───o───o          <- the curated design
                          \
   quilter/exp-a:          o───o───o        <- an experiment timeline
```

## 2. Map of the repository

```
  q-radio.kicad_pro      the KiCad project        ─┐  the "live" project.
  q-radio.kicad_pcb      the live board           ─┤  ALWAYS these names,
  q-radio.kicad_sch      top-level schematic      ─┘  on every branch.
  *.kicad_sch            the other schematic sheets
  praline.kicad_sym      project symbol library   (name kept from upstream
  praline.pretty/        project footprints        so no links break)
  candidates/            pristine Quilter downloads -- QUARANTINE.
    manifest.yaml        the ledger: every candidate, its UUIDs, its origin
  scripts/
    quilter-send.sh      run BEFORE uploading to Quilter
    quilter-import.sh    run AFTER downloading a candidate
    quilter-send.ps1     identical twins for PowerShell users --
    quilter-import.ps1   use whichever terminal you prefer
  docs/WORKFLOW.md       this file
```

**The one big idea:** a Quilter candidate file never keeps its downloaded
name inside the working project. Its identity (job UUID, date, origin) is
recorded in three places instead — the `candidates/` archive, the
manifest, and the commit message — while the working copy is always
renamed to `q-radio.kicad_pcb` so KiCad treats it as *the* project board.

## 3. Golden rules

1. **Commit before you switch branches.** Uncommitted changes follow you
   around or block the switch. The scripts refuse to run with uncommitted
   changes for exactly this reason.
2. **Never open files in `candidates/` with KiCad.** They are evidence.
   Import them with the script instead.
3. **Only edit schematics while on `main`.** Every experiment shares one
   schematic set; keeping schematic edits on one branch avoids chaos
   (section 7 shows how experiments pick those edits up).
4. **When in doubt, run `git status`.** It always tells you which branch
   you are on and what is uncommitted. It never changes anything.

## 4. The five commands you will actually use

```
git status                        where am I, what changed?
git add -A                        stage everything that changed...
git commit -m "what and why"      ...and take the snapshot
git checkout <branch>             stand on a different timeline
git log --oneline --graph --all   draw the whole tree of timelines
```

That last command is your map. Run it often.

---

## 5. Flow A — sending a snapshot to Quilter

Before every upload, stamp the exact state you are sending:

```
./scripts/quilter-send.sh floorplan-b
```

This creates a tag like `q-sent/2026-08-03-floorplan-b` on the current
commit. When a candidate comes back weeks later — possibly after the
design has moved on — the tag still points at the *exact* input state
that produced it.

```
   YOUR FOLDER                          GIT HISTORY
  ┌───────────────────┐
  │ q-radio.kicad_pcb │──(commit)──▶  main: ───o───o───●
  └───────┬───────────┘                                │
          │ upload                                     tag: q-sent/2026-08-03-floorplan-b
          ▼
  ┌───────────────────┐
  │      QUILTER      │  job UUID: c91b52f0-...   <- write this down
  └───────────────────┘
```

## 6. Flow B — what happens when a branch is created

You rarely create branches by hand — `quilter-import.sh` does it — but
here is what it means. Creating a branch adds a second *name* pointing at
an existing commit; nothing is copied yet. The timelines only diverge
when new commits land:

```
  BEFORE                              AFTER  git checkout -b quilter/exp-a
                                              ...and one commit on each side

  main: o───o───●                     main:      o───o───●───o   (schematic fix)
                ▲                                         \
        (you are here)                quilter/exp-a:       ●───o (candidate work)
                                                                ▲
                                                        (you are here)
```

Your folder always shows the files of the ● you are standing on. Switch
with `git checkout main` / `git checkout quilter/exp-a` and watch
`q-radio.kicad_pcb` change identity on disk — same name, different board.

## 7. Flow C — a candidate arrives from Quilter

Download the candidate (say to your Downloads folder), then:

```
./scripts/quilter-import.sh ~/Downloads/candidate_1.kicad_pcb \
      -j c91b52f0-4a2e-...-full-job-uuid \
      -p 8f3a09aa-...-project-uuid \
      -n "quilter run: 2 layers, aggressive via budget"
```

Data flows like this:

```
  ┌─────────┐ download ┌───────────────┐
  │ QUILTER │─────────▶│ ~/Downloads/  │
  └─────────┘          │ candidate_1.. │
                       └──────┬────────┘
                              │ ./scripts/quilter-import.sh
              ┌───────────────┼─────────────────────┐
              ▼               ▼                     ▼
   candidates/c91b52f0/   candidates/         q-radio.kicad_pcb
   candidate_1.kicad_pcb  manifest.yaml       (the live board on branch
   (pristine, frozen      (ledger entry:       quilter/c91b52f0 is now
    forever)               UUIDs, sha256,      this candidate)
                           origin tag)
              └───────────────┴─────────────────────┘
                              │
                              ▼
              one commit on branch quilter/c91b52f0
              with the UUIDs in the message:
                  Quilter-Project: 8f3a09aa-...
                  Quilter-Job:     c91b52f0-...
                  Source-Snapshot: q-sent/2026-08-03-floorplan-b
```

Now open `q-radio.kicad_pro` in KiCad: the candidate *is* the project
board, with schematics, DRC rules, and net classes all attached. A second
candidate from the same job goes onto the **same branch** (just run the
script again); a candidate from a *different* experiment gets its own
branch automatically.

Months later, to find where any board came from:

```
git log                         # read the Quilter-Job: lines
git log --all --grep="Quilter-Job: c91b"    # find a job's commits anywhere
```

## 8. Flow D — the schematic changed; updating an experiment (merge vs rebase)

You fixed something in the schematics on `main` while an experiment was
in flight. The experiment branch is now based on outdated schematics.
Two ways to catch it up:

**Option 1 — merge main into the experiment (recommended).** History is
added, never rewritten; nothing can be lost:

```
  BEFORE                                AFTER   git checkout quilter/exp-a
                                                git merge main

  main:    o───A───S  (S = sch fix)     main:    o───A───S
                \                                     \    \
  exp-a:         B───C                  exp-a:         B───C───M
                                                               ▲
                                        M has C's board file AND S's schematics
```

**Option 2 — rebase the experiment onto main.** Rebase *replays* your
experiment commits on top of the new main, as if the experiment had
started after the schematic fix. History looks cleaner, but the old
commits are rewritten into new ones (B→B', C→C'):

```
  BEFORE   git checkout quilter/exp-a    AFTER
           git rebase main

  main:    o───A───S                     main:    o───A───S
                \                                          \
  exp-a:         B───C                   exp-a:             B'───C'
                                         (B and C re-created on the new base)
```

Use merge until you are comfortable; the result in your folder is the
same. **Never rebase a branch you have already pushed and shared.**

In either case, afterwards open KiCad and run
**Tools → Update PCB from Schematic** so the board picks up the netlist
changes, then commit that.

## 9. Flow E — picking the winner

Say three experiments produced three boards, and `quilter/exp-b` wins:

```
  BEFORE                                     AFTER

  main:  ──o───S                             main:  ──o───S───────────M   ◀ the winner,
             ├─────────┐                                ├─────────┐  /      now the
  exp-a:     │  o───o  │ (loser)             exp-a:     │  o───o  │ /       official board
             │         │                                │      ▲  │/
  exp-b:     o───o───o │ (WINNER)            exp-b:     o───o──┼──o
                       │                                       │
  exp-c:               o───o (loser)         exp-c:            o───o
                                                                   ▲
                                             losers stay forever, tagged:
                                             archive/quilter/exp-a, exp-c
```

The commands:

```
git checkout main
git merge --no-ff quilter/exp-b -m "Adopt Quilter candidate from exp-b as the board

Quilter-Job: c91b52f0-...   (copy from the import commit: git log quilter/exp-b)"
```

If git reports a **conflict** on `q-radio.kicad_pcb` — normal, because
board files are deliberately marked "do not auto-merge" — resolve it by
taking the winner's board wholesale:

```
git checkout --theirs q-radio.kicad_pcb      # "theirs" = the branch being merged in
git add q-radio.kicad_pcb
git commit
```

Then archive the losers as permanent, explorable sticky notes (this does
NOT delete anything — it names their endpoints so they are easy to find):

```
git tag archive/quilter/exp-a quilter/exp-a
git tag archive/quilter/exp-c quilter/exp-c
```

Never delete experiment branches. Disk cost is negligible; the explorable
history is the whole point. To revisit a loser any time:
`git checkout quilter/exp-a` — your folder becomes that board again.

Finally, update the winner's `status:` to `winner` (and the losers to
`rejected`) in `candidates/manifest.yaml`, and mark project milestones as
you go:

```
git tag v1.3-placed        # examples: -floorplan, -placed, -routed, -drc-clean
```

## 10. Schematic variants (e.g. removing testpoints)

Two different things are both called "removing testpoints" — pick the
right tool:

**A. Assembly variant — pads stay, parts not fitted.** No branch needed.
In Eeschema, symbol properties → tick "Do not populate" (and "Exclude
from BOM"). Netlist and board are unchanged; this lives on `main`.

**B. Design variant — testpoints gone from netlist and board** (what you
want when giving Quilter an easier routing job). This forks the design,
so it gets its own branch layer *between* `main` and the experiments:

```
  main:               o───S1─────────S2──────────────   full design, all TPs
                           \          \  (merge main → variant on sch changes)
  variant/tp-none:          V1────────M────●            V1 = TPs excluded
                                           │    tag: q-sent/...-tp-none-a
  quilter/3fa85f64:                         C1───C2     candidates w/o TPs
```

**Prefer attribute flips over deletion.** Don't delete testpoint symbols
on the variant branch — instead tick "Exclude from board" in each
symbol's properties, then Tools → Update PCB from Schematic. The
footprints vanish from the board (Quilter never sees them), but the
schematic diff is a few one-line attribute changes: reversible, easy to
define partial sets, and far less likely to conflict when merging
schematic fixes down from `main`.

Creating a variant:

```
git checkout main
git checkout -b variant/tp-none
# in KiCad: flip "Exclude from board" on the testpoints,
#           Tools -> Update PCB from Schematic, save
git add -A && git commit -m "Variant tp-none: exclude all testpoints from board"
```

Everything downstream already works unchanged: run
`./scripts/quilter-send.sh tp-none-<label>` while standing ON the
variant branch (the snapshot tag lands there), and `quilter-import.sh`
bases the experiment branch on that tag automatically. The manifest's
`schematic_commit` field records which variant each candidate was routed
against.

The amended golden rule: schematic edits happen on `main` — *except* a
variant's own defining edits, which live on its `variant/*` branch. When
`main` gets a schematic fix: `git checkout variant/tp-none && git merge
main`. If a sheet conflicts (both sides touched it), take main's copy of
that sheet (`git checkout main -- <sheet>.kicad_sch`), re-flip the few
exclude attributes in it, then `git add` and commit the merge.

Winners with variants: merge the winning `quilter/*` branch into its
**variant** branch first (same procedure as section 9). Then either
promote the variant to be the product — `git checkout main && git merge
--no-ff variant/tp-none` (the full-testpoint design stays reachable at
every earlier main commit forever) — or, if `main` should remain the
full reference design, release from the variant branch with tags like
`v1.3-tp-none-released`. Promoting to main keeps "main = what we ship"
true, which is the easier rule to live with.

## 11. Syncing with GitHub

Your GitHub fork (`xjordanx/q-radio`) is the off-site copy. After
committing locally, publish with:

```
git push origin main                 # push the current branch
git push origin quilter/exp-b        # experiment branches too
git push origin --tags               # tags are NOT pushed automatically
```

And `git pull` brings down anything pushed from another machine. If a
push asks for credentials, GitHub wants a "personal access token" instead
of your password — create one at github.com → Settings → Developer
settings → Personal access tokens.

## 12. When something goes wrong

* `git status` first. Always safe, always explains.
* Threw the working folder into a bad state, want the last snapshot back:
  `git checkout -- .`  (discards ALL uncommitted changes — be sure).
* Committed to the wrong branch: don't panic, nothing is lost; ask for
  help or search "git move commit to another branch".
* KiCad won't open something / files look scrambled: check you are on the
  branch you think you are on (`git status`), and that KiCad wasn't open
  with unsaved changes while you switched branches. Close KiCad before
  switching branches — that habit prevents nearly all confusion.

## 13. Cheat sheet

```
BEFORE uploading to Quilter      ./scripts/quilter-send.sh <label>
AFTER downloading a candidate    ./scripts/quilter-import.sh <file> -j <job-uuid>
See the whole tree               git log --oneline --graph --all
Switch experiment                git checkout quilter/<name>     (close KiCad first)
Back to the main design          git checkout main
Save a snapshot                  git add -A && git commit -m "why"
Catch experiment up to main      git checkout quilter/<name> && git merge main
Make a schematic variant         git checkout main && git checkout -b variant/<name>
Crown a winner                   git checkout main && git merge --no-ff quilter/<name>
Find a job's commits             git log --all --grep="Quilter-Job: <uuid-start>"
Publish everything               git push origin --all && git push origin --tags
```
