# UCSD p-System IV.0 on MultiComp — working notes

## The current build

Four pieces make a working system. These are the only files needed to rebuild;
everything else in the history is superseded.

| Piece | File | Size | Role |
|-------|------|------|------|
| Primary bootstrap | `PASBOOT_MULTICOMP_Z80_v16.ASM` | 354 | CP/M `.COM` at 0100h. Loads 17 sectors to 8200h and jumps. |
| Secondary bootstrap | `SECBOOT_MULTICOMP_v21.ASM` | 517 | Copies the shim to E200h, loads SYSTEM.INTERP, pushes the 13-word handoff. |
| SBIOS shim | `SHIM_MULTICOMP_v21.ASM` | 972 | Runs at E200h. Disk translation, direct ACIA console, VT52→ANSI, keyboard ring buffer, cursor restore after erase. |
| Volume | `PSYSTEM.VOL` | 2400 blk | 25 files. MISCINFO width patched 80→79. |

Image layout (drive P = unit 15, base `15 * 8388608`):

```
base + 384      17 x 128-byte sectors = the loaded window
                  offset    0   SECBOOT   (must fit in 1024 bytes)
                  offset 1024   SHIM      (must fit in 1024 bytes: E200h..E5FFh)
base + 16384    the p-System volume
32768           PASBOOT as a CP/M .COM, record count 3 at 16384+15
```

Both size limits are hard and have been hit more than once. Check before flashing.


Boots UCSD Pascal on Grant Searle's MultiComp CP/M 2.2 (CBIOS 2.0), from a
`.COM` launched at the `A>` prompt. Everything below was established on real
hardware, not simulated.

## The chain

```
A>PASBOOT                        PASBOOT_MULTICOMP_Z80_v16.bin   (drive A, 354 bytes)
  reads 17 sectors -> 8200h      drive P track 0 sector 3
  checks C5 signature, pushes 12 params, JP 8200h
SECBOOT                          SECBOOT_MULTICOMP_v17.bin       (517 bytes @8200h)
  copies shim 8600h -> E300h, pokes its two variables
  finds SYSTEM.INTERP in the p-System directory, loads it to 0000h
  carves buffers, pushes 12 params + boot unit, JP 0200h
SHIM                             SHIM_MULTICOMP_v3.bin           (453 bytes @E300h)
  the SBIOS the interpreter talks to, for the rest of the session
```

Disk image layout (`cpm-blank-ucsd.img`, 128MB, 16 x 8MB logical drives):

| what | where |
|---|---|
| PASBOOT.COM data | file offset 32768 (drive A block 4); dir entry 16384, RC at 16399 |
| SECBOOT | drive P track 0 sector 3 = offset 125829504 |
| shim image | same 17-sector window, offset +1024 (address 8600h at run time) |
| p-System volume | drive P track 1 = offset 125845504 |

Drive P = unit 15. `offset = drive*8388608 + track*16384 + hostsector*512`,
confirmed against Grant's `setLBAaddr`.

## Memory map after handoff

```
0000h..35FFh   SYSTEM.INTERP        (owns page zero — see below)
3600h..E0FFh   p-System workspace   43776 bytes
E100h..E17Fh   sector buffer  ) carved by SECBOOT from NEWTOP=E200h
E180h..E1FFh   sector table   )
E200h..E5FFh   the shim             above TOPRAM, so it survives; 1024 reserved
E600h..        Grant's CBIOS
FF00h..FFFFh   interpreter's p-code dispatch table
```

## Why each workaround exists

Nothing here is decorative. Each was a failure diagnosed on hardware.

1. **INTERPBASE = LOWMEMORY = 0000h.** The interpreter's dispatch table has to
   own page zero: its opcode dispatch does `LD H,0` with a conditional `DEC H`,
   putting opcodes 0-127 at FF00h and 128-255 at 0000h. Its cold start at 243Bh
   only makes sense at base 0.

2. **13 words pushed, not 12.** The cold start pops the boot unit (4) *then*
   exactly 12 parameter words. Pushing only 12 leaves everything off by two
   bytes and it dies silently with no SBIOS call.

3. **TRACKS = 77, not 512.** The interpreter range-checks the computed track
   with a single-byte `CP` at 20EDh. 512 = 0200h has a low byte of 00h, so every
   track failed and it returned p-System I/O error 17 before any transfer.

4. **MAXSECTORS/MAXBYTES are replaced by carved buffer ADDRESSES**, and TOPRAM
   lowered, exactly as the real z80pack tertbot does. Passing the raw counts
   (128/128) points the interpreter's sector buffer at 0080h, inside its own code.

5. **Shim forces drive 15 and returns HL=0000h from SELDSK.** The p-System's
   convention is HL=0 for success; Grant returns a DPH pointer, which the
   interpreter reads as failure and abandons the read.

6. **Shim zeroes B on SETTRK/SETSEC.** The p-System CBIOS takes 8-bit values in
   C alone; Grant's stores the full BC.

7. **Shim decrements the sector.** The interpreter emits 1-based sectors
   (`INC L` at 211Ah); Grant's `rwoper` uses `seksec` as a raw 0-based index.

8. **Shim has its own ACIA console driver.** Grant's const/conin/conout all read
   `iobyte` at 0003h, which the interpreter overwrites when it loads at 0000h.
   The channel is chosen from an iobyte captured *before* the load, using Grant's
   own rule: `(iobyte AND 3) == 1` selects ACIA0, else ACIA1.

9. **Shim lives at E300h, above TOPRAM.** Inside the p-System's memory it gets
   overwritten mid-run — observed marching 825Ah, 82DAh, 835Ah, 83DAh through
   SECBOOT during a load, then death. It must be assembled at its final address
   (absolute jump table), hence a separate source file.

10. **VT52 -> ANSI translation in CONOUT.** MISCINFO can only express a
    single-character escape lead-in, so ANSI is impossible to configure directly.
    Udo Munk's and RomWBW's ports use the same trick: insert `[` after every
    outbound ESC. What that `[` must be followed by is documented in
    *MultiComp's actual terminal capabilities* below — the naive insert is wrong.

12. **Every control code the p-System emits is padded with five NULs**, and
    MultiComp renders each NUL as a blank. That, and not any escape-sequence
    problem, was the mysterious ~5-column indent on the top line and the
    apparent line wrap. The shim discards 00h outright.

13. **The shim tracks the cursor itself** and synthesises cursor left/right as
    absolute positioning, because MultiComp implements neither. See below.

11. **Shim forces C=1 on WRITE** (CP/M write-through). The p-System doesn't set
    a write type and Grant's `write` stores whatever is in C as `wrtype`.

## MultiComp's actual terminal capabilities

This is the least guessable thing in the whole project and it cost three wrong
guesses before it was instrumented. Measured on hardware with SECBOOT v18/v19/v20,
which painted labelled markers and photographed the result:

| Sequence      | Result |
|---------------|--------|
| `ESC [ r ; c H` | **works** |
| `ESC [ 1 A`     | **works** (up one row, column preserved) |
| `ESC [ 1 B`     | **works** |
| `ESC [ 0 K`     | **works** (erase to end of line) |
| `ESC [ 0 J`     | **works** (erase to end of screen) |
| `ESC [ H`       | ignored — no parameter |
| `ESC [ K`       | ignored — no parameter |
| `ESC [ J`       | ignored — no parameter |
| `ESC [ 2 J`     | ignored |
| `ESC [ 1 C`     | **works** (the early "not implemented" reading was wrong) |
| `ESC [ 1 D`     | misbehaves — the marker landed to the RIGHT. Use plain BS (08h) |
| `ESC [ 0 K`     | erases correctly, **but then moves the cursor to HOME** |
| `ESC [ 2 K`     | ignored entirely — no erase, cursor unmoved |
| `ESC [ 1 K`     | not implemented — prints a literal `K` |
| bare LF (0Ah)   | true line feed, column preserved (not CR+LF) |
| bare CR (0Dh)   | returns to column 1 |

Two rules follow. **MultiComp requires an explicit parameter on everything** —
the parameterless forms are silently dropped, not defaulted. And **it has no
cursor left/right at all**; emitting them actively corrupts the display, because
the bytes land on screen as text.

Shim v8 and earlier emitted `ESC [ J`, `ESC [ K` and `ESC [ A` — all three
parameterless, all three ignored. That is why the editor could never erase
anything and appeared to have lost the cursor. It hadn't; the screen simply
never changed.

Shim v9 addresses this by keeping its own row/column (`CURROW`/`CURCOL`),
updated by printable characters, CR, LF, BS, the cursor sequences, and by
parsing the digits out of SYSTEM.PASCAL's ANSI GOTOXY. Left and right are then
expressed as `ESC [ row ; col H`, which works. Tracking resyncs on every
absolute positioning, so drift can't accumulate, and all updates clamp rather
than wrap.

Cursor tracking pushed the shim past its old 640-byte allowance, so from
SECBOOT v21 the shim lives at **E200h with 1024 bytes** instead of E300h/768.
That costs the p-System 256 bytes of workspace; the highest address it has ever
been observed touching is DA32h, so there is ample headroom.

MISCINFO's nominated screen codes, for reference: lead-in `ESC`, home `H`,
erase-EOS `J`, erase-EOL `K`, cursor-right `C`, cursor-up `A`, left = plain
backspace (08h).

## THE ROOT CAUSE — ESC[0K homes the cursor

Found by the v30 probe. Rows 1-5 were filled with ten identical letters each,
the cursor was placed at row 3 column 5, `ESC[0K` was issued, and a single `@`
was written **with no positioning in between**. The result:

```
row 1:  @AAAAAAAAA      <- the @ landed HERE
row 3:  CCCC            <- correctly erased from column 5
```

The erase itself is perfect — row 3 lost exactly columns 5 onward and rows 1, 2,
4 and 5 were untouched. But the cursor ended up at row 1 column 1.

So every erase-to-end-of-line silently teleported the cursor to the top left,
and whatever the editor drew next landed on row 1. That one behaviour accounts
for every symptom chased across two sessions:

* text drawn one row too high
* the Edit menu appearing over the first line of text
* the Insert banner landing on the text
* text landing in the wrong place during redraws
* the `.7j]` tail of the Edit prompt surviving under the shorter Insert banner

**The fix (v21):** `ESC K` emits `ESC[0K` and then `ESC[row;colH` to put the
cursor back. `ESC J` gets the same treatment — whether `ESC[0J` also homes was
never measured, and restoring afterwards costs nothing if it does not.

The alternatives were no good: `ESC[2K` does nothing at all and `ESC[1K` prints
a literal `K`, so `ESC[0K` has to be used and then corrected.

This does mean cursor tracking came back after v18 deleted it — but the reason
for deleting it does not apply here. It was previously used to SYNTHESISE
cursor-right, where drift accumulates into a visibly wandering cursor. Now it is
used only to restore position immediately after an erase, and the editor issues
an absolute `ESC[r;cH` right before almost every erase, so the tracked value is
freshly resynchronised at the exact moment it is needed.

## Shim version state

| Build | Status |
|-------|--------|
| v9  | boots. Translation proven correct by simulation against a captured byte stream. |
| v10 | boots. v9 + NUL discarded in every state + COLINC wraps. The NUL change fixed nothing (see below) but is harmless. |
| v12 | **HANGS at boot, cause unknown.** Buffered-parser rewrite, ~1007 bytes -- within 17 bytes of overflowing the region, so size is a suspect as much as logic. Better design; unproven. Do not build on it. |
| v15 | Built on a misreading of a photograph. Forces non-';' terminators to 'H'. Unnecessary; ignore. |
| v16 | v10 + NUL costs time instead of being discarded. Tested: no improvement; the timing theory was wrong. |
| v17 | v10 + KEYBOARD RING BUFFER. Fixed the lost keystrokes on entering insert mode -- the ACIA has a one-byte receive register and no buffer, so anything typed while the editor painted its banner was overwritten. The shim now grabs incoming characters from inside the transmit wait loop. |
| v18 | v17 with all cursor tracking deleted, after the v24 probe showed cursor-right works and never needed synthesising. |
| v21 | **CURRENT AND WORKING.** v18 + restore the cursor after every erase. See above. |

Diagnostic builds, all of which render the byte stream as text rather than acting
on it, and none of which are production: v10-DIAG (input, NULs hidden -- a
mistake), v11-DIAG (input, NULs shown as `.`), v13-DIAG (output, but built on the
hanging v12, so useless), v14-DIAG (output, built on v10 -- this is the one that
worked).

## What the padding NULs are actually for

The p-System pads every MISCINFO control code with five NULs. MultiComp draws a
NUL as a blank, which is what produced the old ~5-column indent, so v9 through
v15 discarded them.

Discarding them was right. Discarding them **without spending the time** was not.
They exist to give the terminal time to finish, and `ESC[0J` has up to 1920 cells
to clear. v16 keeps them off the screen but burns the delay.

This is the current best explanation for the editor fault and is **not yet
confirmed**. The evidence for it is indirect but consistent:

* v14-DIAG showed the shim's output is correct -- only measured forms, and
  `ESC[1;1H ESC[1;1H ESC[0K` goes out immediately before the menu.
* The menu still does not land on row 1.
* Where it works, the erase is *last*: `ESC[1;1H ESC[0K <text>` (main menu).
  Where it fails, sequences *follow* an erase: `ESC[2;1H ESC[0J ESC[2;1H ...`
* Every probe ever run put `ESC[0J` at the end of a test with nothing after it,
  so "does a sequence survive immediately after an erase" was never measured.

**v16 was tested and made no difference.** That weakens the timing theory but
does not kill it -- PADLOOP is only ~0.4 ms per NUL, and nobody has established
how long MultiComp actually needs.

## RESOLVED -- the terminal is not at fault

Everything so far has been measured with the p-System in the loop. What has
never been measured is MultiComp on its own:

> Does a positioning sequence survive when it arrives immediately after an
> erase? i.e. does `ESC[5;1H ESC[0J ESC[1;1H MARKER` put MARKER on row 1?

**ANSWERED by the SECBOOT v22 probe: YES, all four tests passed.** MultiComp
honours a position immediately after `ESC[0J`, with or without a delay, and
after `ESC[0K` as well. The terminal is fine. v16's delay addresses a problem
that does not exist -- harmless, but pointless.

Also checked: our `SYSTEM.MISCINFO` is byte-identical to RomWBW's apart from the
single width byte we changed (80 -> 79). It is not corrupt, and we are running
RomWBW's exact terminal configuration. The directory-looking bytes at the start
of the 194-byte record are present in RomWBW's working copy too, so they are
leftover padding the p-System never reads, not damage.

### Where that leaves it

All three components have now been measured INDIVIDUALLY and all three are
correct:

1. the p-System emits well-formed sequences        (v11-DIAG, input)
2. the shim translates them to measured forms only (v14-DIAG, output)
3. MultiComp honours those forms                   (v22 probe)

Those cannot all be true alongside a broken display, so something in the
interaction is still unobserved -- or the remaining fault is smaller than the
descriptions suggest. The v14-DIAG output transcript, read literally, places the
menu on row 1 and the text on row 2, which is correct behaviour.

**Next: photograph the REAL screen** with production v16, on entry to the editor
and after ctrl-C. Every recent photo has been of a diagnostic build, which by
design does no positioning at all, so nobody has actually looked at the working
display since the fault was last described.

Build it as a SECBOOT probe in the style of v18-v20: it runs before the
p-System loads, uses the raw ACIA driver, paints labelled markers, one photo.
Worth including in the same probe:

* erase then position, back to back (the suspect case)
* the same pair with a delay between them (isolates timing from parsing)
* two positioning sequences back to back, no erase (control)
* `ESC[0K` then position (does erase-to-EOL misbehave too, or only EOS?)

If the fault reproduces with no p-System present, it is MultiComp's and the
shim must work around it -- most likely by never emitting anything straight
after an erase. If it does not reproduce, the fault is back in our court and
the shim's output, though well formed, must differ from the probe in some way
we have not yet identified.

## Editor behaviour that is NOT a bug

Confirmed against other systems, so that time is not spent re-investigating it:

* **Text disappears when you press return in insert mode.** Verified against Udo
  Munk's emulator running the same editor — the editor clears and repaints on
  accept. An earlier note here wrongly listed this as a symptom of the `ESC[0K`
  fault. What was ours was text landing in the WRONG PLACE, not the fact that it
  vanishes and comes back.
* **No cursor movement in insert mode.** Backspace deletes a character rather
  than moving; `<del>` deletes a line. The banner says so. Confirmed by the user
  against other versions. Cursor-left and Backspace are the same byte (08h), so
  they cannot behave differently.
* **Insert does not reflow the tail of the line until you accept.**
* **A persistent direction flag** set by `>` and `<` governs Find, Delete and
  Copy.
* **Repeat counts:** a digit typed before a command repeats it.

Arrow keys in this distribution are WordStar-style: `^E` up, `^X` down, `^S`
left, `^D` right (from RomWBW's README).

## Reading escape sequences off photographs

Don't. Two separate diagnoses in one session were built on an `H` misread as an
`A`, and both cost a flash cycle. If a diagnostic has to show an ambiguous
character, print it with its hex code or as a spelled-out marker.

More generally: five hypotheses in that session were killed by measurement --
ESC-`[` mangling, GOTOXY not installed, NULs inside the sequence, a malformed
`ESC[3;1A`, and the shim's translation being wrong. Instrument first.

## The mismatched pair (revised — the earlier alarm was wrong)

`SYSTEM.PASCAL` and `SYSTEM.MISCINFO` come from **RomWBW's** p-System port;
`SYSTEM.INTERP` is **ours**, from SYSCPM1. They are different builds and that is
worth remembering, but the specific danger recorded here previously was a
mistake and has been withdrawn.

**What was claimed:** that our build has `SOFTOPS` where RomWBW's has
`STRINGOP` in the segment dictionary, so anything using `REAL` might dispatch to
the wrong segment.

**What is actually true**, checked by dumping the dictionaries:

* `SYSTEM.INTERP` is native Z80 code, not a p-code codefile. It has no segment
  dictionary at all, so it cannot conflict with one. The original comparison
  must have been between two `SYSTEM.PASCAL` files, not between the interpreter
  and the OS.
* The `SYSTEM.PASCAL` we actually run has an ordinary, self-consistent
  dictionary: `KERNEL`, `PRINTERR`, `INITIALI`, `GETCMD`, `PASCALIO`, `EXTRAIO`,
  `HEAPOPS`, `EXTRAHEA`, **`STRINGOP` at slot 8**, `SCREENOP`, `SEGSCINI`,
  `CONCURRE`, `PERMHEAP`, `OSUTIL`, `FILEOPS`, `USERPROG`.
* `SOFTOPS` is a segment *referenced from inside* `SYSTEM.PASCAL` and
  `SYSTEM.COMPILER` — software floating point, as expected — and it is present
  in RomWBW's original volume too. Nothing is displaced.

**The real remaining question** is narrower and ordinary: does our
`SYSTEM.INTERP` implement the floating-point p-codes that the compiler emits and
`SOFTOPS` relies on? That is a plain "does it work" question, not a segment
numbering hazard. A short program doing some `REAL` arithmetic and printing the
result answers it.

## Floating point — not supported, and why

`REAL` arithmetic fails at runtime with **"Unimplemented Instruction"**. The
program compiles cleanly; the p-machine then hits a floating-point opcode our
`SYSTEM.INTERP` does not implement.

This is a build option, not damage. The Adaptable distribution ships paired
interpreters and the adaptation process had you choose one:

| File | Size | |
|------|------|--|
| `INTERP.Z.CODE`  | 11264 | Z80, no floating point |
| `INTERP.ZF.CODE` | 12800 | Z80, **F** = with floating point |
| `INTERP.8.CODE`  | 11264 | 8080, no floating point |
| `INTERP.8F.CODE` | 12800 | 8080, with floating point |

About 1.5K more for floating point — and since the interpreter is memory
resident, that comes permanently out of user program space. On a 64K machine
that is a real cost for a feature many programs never touch.

### What was tried

RomWBW's `psys.vol` carries a `SYSTEM.INTERP` of 14336 bytes against our 13824,
and would also have made `SYSTEM.INTERP` + `SYSTEM.PASCAL` + `SYSTEM.MISCINFO` a
matched set from one build for the first time. It was prepared as
`PSYSTEM_ROMWBW.VOL` (MISCINFO width patched to 79, volume size reduced to 2400
blocks so it fits the declared geometry) and **it does not boot**: PASBOOT prints
its banner and the machine hangs.

The hang is before any p-System output, so the volume size is innocent — the
volume header is never read that early. It is either SECBOOT failing on that
volume, or their interpreter loading correctly and rejecting our 13-word
handoff.

### If anyone wants to pursue it

1. Instrument SECBOOT to print a marker at each stage — directory read, file
   found, block count, load complete, about to jump. One flash cycle says which
   half failed.
2. If SECBOOT is fine, RomWBW's interpreter wants a different handoff, which
   means reverse-engineering it from their own bootstrap (`CPMBOOT.CODE` or
   `TERTBOOT.CODE`, both present in their volume).
3. `INTERP.ZF.CODE` cannot simply be renamed to `SYSTEM.INTERP` — it is a p-code
   **codefile** with a segment dictionary whose segment 0 is named `INTERP`,
   whereas a working `SYSTEM.INTERP` is a raw Z80 binary beginning with the
   p-code dispatch table. Something in the adaptation process performs that
   conversion, and it would have to be understood.

Not worth the cycles unless `REAL` is actually needed. Integer Pascal, the
compiler, the editor and disk writes all work.

## Volume variants (in `C:\temp\cpm`)

| file | SYSTEM.PASCAL | MISCINFO | notes |
|---|---|---|---|
| `PSYSTEM_ANSI_ROMMI.VOL` | RomWBW | RomWBW | **currently flashed**; working |
| `PSYSTEM_ANSI.VOL` | RomWBW | z80pack | ANSI screen, but accept key is Ctrl-Z |
| `PSYSTEM_STOCKPASCAL.VOL` | ours | z80pack | matched pair, but no cursor addressing |

2400 blocks, 25 files, ~900KB free. Built from the `.VOL` files in `C:\temp\cpm`
preserving each file's original `dfkind` and `dlastbyte`.

Volume-build gotcha: the volume entry's `dvkind` is at directory offset **1024+4**,
not file offset 4. Getting that wrong writes `E5E5` and the system throws
`Exec err 13/15` then `STACK OVERFLOW`.

## Keyboard

p-System IV.0 cannot parse incoming escape sequences, so arrow keys are
impossible. Bound WordStar-style instead:

| key | function |
|---|---|
| Ctrl-E / Ctrl-X | up / down |
| Ctrl-S / Ctrl-D | left / right |
| Ctrl-C | accept (with RomWBW MISCINFO) |
| Ctrl-[ | ESC |

`SETUP.CODE` is on the volume and now drivable if these need changing.

## Still untested

- the compiler
- anything using `REAL` (see `SOFTOPS` above)
- sustained disk writes (a single editor save is confirmed working)
- memory headroom is 512 bytes; the p-System was observed reaching DA32h

## Rebuilding

Only SECBOOT knows the shim's address and image offset, via
`SHIMDEST`/`SHIMSRC`/`SHIMLEN`/`NEWTOP`. If the shim grows past 640 bytes or
moves, those four constants and the shim's `ORG` must change together.

`PASBOOT` gates its jump on SECBOOT's first byte being `C5` (PUSH BC). Keep that
instruction first, or it halts with "BOOTSTRAP CORRUPT" — this caught a real
bad handoff during development.
