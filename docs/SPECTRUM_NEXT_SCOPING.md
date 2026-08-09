# Porting UCSD p-System to the ZX Spectrum Next — scoping notes

Written after the MultiComp port was working, from analysis of the Next's CP/M
distribution. **Nothing here has been tested on hardware.** It is a survey of
what would be involved, and of one very large piece of good news.

## Summary

A Next port looks *more* tractable than the MultiComp one, not less. The problem
that consumed almost all the effort on MultiComp — the terminal — does not exist
on the Next. What remains is the disk and memory work, and even that reuses most
of the existing design.

## Source material examined

| File | What it is |
|------|------------|
| `cpm-a.p3d` | 16 MB CP/M 3 system drive, 31 files (CCP, PIP, ED, SID, SET, SHOW, GENCOM, plus Next-specific `NEXTREG`, `COLOURS`, `IMPORT`/`EXPORT`, `TERMINFO`, `TERMSIZE`) |
| `cpm-e.p3d` | 16 MB data drive, 83 files — M80/L80/LIB/CREF80, FORTRAN-80, MBASIC, COBOL-80, Turbo Pascal, CRT driver sources |
| `cpm/system/nextbios.prl` | The BIOS — a **489-byte PRL stub** |
| `cpm/system/biosext.bin` | *"ZX Spectrum Next BIOS v0.97 (c) 2019-2024 Garry Lancaster"* — the real BIOS, living outside the 64K space |
| `cpm/system/bnkbdos3.spr`, `resbdos3.spr` | Banked and resident BDOS |

`TERMSIZE.COM` identifies the system as **CP/M Version 3.0, Caldera 1998**.

## The good news: the terminal is a Zenith Z-19

`TERMINFO.COM` states it directly:

> *"The terminal emulates most features of the Zenith Z-19 terminal, so choose
> one of the following terminal types if possible: Zenith Z-19, Heathkit H-19"*

The Z-19 is a VT52-family terminal using **single-character escape sequences**,
which is exactly and precisely what UCSD's `SYSTEM.MISCINFO` was designed to
describe. Documented as supported:

| Sequence | Effect |
|----------|--------|
| `ESC H` | cursor home |
| `ESC A` `ESC B` `ESC C` `ESC D` | up / down / right / left |
| `ESC J` | erase to end of screen |
| `ESC K` | erase to end of line |
| `ESC Y r c` | direct cursor addressing, both values biased by 32 |
| `ESC I` | reverse index, scrolling if required |
| `ESC L` / `ESC M` | insert / delete line |
| `ESC E` | clear and home |
| `ESC n` | cursor position report |

Also present: a full ANSI mode with an explicit compatibility switch, insert and
delete character, colour, italics, underline, reverse video, and selectable
screen size up to 32 lines via `TERMSIZE.COM` (default 24x80).

**Consequences for the port.** Essentially the whole MultiComp shim disappears:

* No `[`-insertion hack. MISCINFO's one-character lead-in is all a Z-19 needs.
* No cursor tracking, no synthesised cursor-right, no erase-then-restore.
* `ESC Y r c` biased by 32 is *already implemented* by the `GOTOXY.TEXT` sitting
  unused in our volume: `WRITE (CHR(27),'Y',CHR(Y+32),CHR(X+32))`.
* A cursor position report exists, which MultiComp has no equivalent of.

For comparison, MultiComp needed: parameters on every sequence, no cursor
left/right (later disproved), a `[` inserted after every ESC, and an `ESC[0K`
that silently homes the cursor. None of that applies here.

Keyboard mappings are documented too — arrows map to `CTRL-E`/`CTRL-X`/
`CTRL-S`/`CTRL-D`, matching what the p-System distribution already expects.

## The BIOS is reachable the same way

`nextbios.prl` is page-relocatable, 489 bytes, and carries the full 33-entry
CP/M 3 jump table. Critically, **the first 17 entries are in exactly the CP/M
2.2 order**:

```
 0 BOOT   1 WBOOT  2 CONST  3 CONIN   4 CONOUT  5 LIST
 6 AUXOUT 7 AUXIN  8 HOME   9 SELDSK 10 SETTRK 11 SETSEC
12 SETDMA 13 READ 14 WRITE 15 LISTST 16 SECTRAN
```

CP/M 3 *appends* its extras (MULTIO, FLUSH, MOVE, TIME, SELMEM, SETBNK, XMOVE,
USERF) rather than rearranging. Our shim uses only the first 17.

Locating the BIOS also transfers unchanged: CP/M 3 still places `JP WBOOT` at
0000h, so reading the word at 0001h and subtracting 3 gives the BIOS base — the
same trick PASBOOT already uses. The stub being relocatable does not matter.

### What the disk entries actually do

Disassembled from the stub:

```
SETTRK   LD (varA),BC        16-bit track  in BC
SETSEC   LD (varB),BC        16-bit sector in BC
SETDMA   LD (varC),BC        DMA address   in BC, then copies the default bank
SETBNK   LD (bank),A         sets the bank the DMA buffer lives in
SELDSK   indexes a DPH table, returns the DPH pointer in HL
READ     LD IX,<parmblock> : CALL <common>
WRITE    LD IX,<parmblock> : CALL <common>
```

Two familiar consequences:

* `SETTRK`/`SETSEC` take **full 16-bit values in BC**, as Grant's do, whereas the
  p-System supplies 8-bit values in C alone. The shim's existing `LD B,0` fix
  applies unchanged.
* `SELDSK` returns a **DPH pointer**, whereas the p-System expects **HL=0 for
  success**. The shim's existing inversion applies unchanged.

## ANSWERS — from a full disassembly of nextbios.prl

The 489-byte stub has now been disassembled completely. All three questions are
resolved, and the news is good.

### 1. Banking — port 1FFDh, and C000h is common to both configurations

`SELMEM` is the whole mechanism:

```
SELMEM: LD (curbank),A
        PUSH BC
        AND  01
        ADD  A,A          ; x2
        ADD  A,A          ; x4
        XOR  05
        LD   BC,1FFD
        OUT  (C),A
        POP  BC
        RET
```

Port **1FFDh** is the +3/+2A paging port. The arithmetic yields only two values:

| SELMEM(A) | value out | +3 special paging config | banks at 0000/4000/8000/C000 |
|-----------|-----------|--------------------------|------------------------------|
| 1 (TPA)   | 01h       | special mode, config 0   | 0, 1, 2, **3** |
| 0 (system)| 05h       | special mode, config 2   | 4, 5, 6, **3** |

**Bank 3 sits at C000h in both configurations.** That is the CP/M 3 common area,
and it is why the absolute addresses in the stub — `FAD0h` (drive table), `FE00h`
and `FE22h`–`FE2Ah` (device tables) — are not relocated: they are fixed
structures in common memory.

Every BIOS entry follows the same pattern: save SP, switch to a local stack
inside the stub, `SELMEM(0)` to page in the system bank, call a routine in the
7000h–7FFFh region (which only exists in that configuration), then `SELMEM` back
to the caller's bank and restore SP.

**Consequence for the port:** this is *less* intrusive than it first appears. The
p-System would live in the TPA configuration at 0000h–BFFFh. During a BIOS call
its memory is temporarily unmapped, but the BIOS restores the configuration
before returning, so nothing is lost. The stub's own stack is in common memory,
so it does not touch the p-System's.

### 2. Common memory starts at C000h — so TOPRAM = C000h

Directly implied by bank 3 being common. The p-System therefore gets
**0000h–BFFFh = 48K**, against 43K on MultiComp. More room, not less.

### 3. Disk — the shim's existing fixes apply, plus one new one

```
SETTRK   LD (trk),BC       full 16-bit track in BC
SETSEC   LD (sec),BC       full 16-bit sector in BC
SETDMA   LD (dma),BC : LD A,(curbank)   <-- falls through into SETBNK
SETBNK   LD (dmabank),A
SELDSK   LD B,0 : LD (drv),BC : LD HL,FAD0 : ADD HL,BC : ADD HL,BC
         : LD A,(HL) : INC HL : LD H,(HL) : LD L,A : RET
SECTRAN  LD H,B : LD L,C : RET          identity, no skew
HOME     LD BC,0 : falls into SETTRK
READ     PUSH IX : LD IX,7C98 : CALL common
WRITE    PUSH IX : LD IX,7CC8 : CALL common
```

* `SETTRK`/`SETSEC` take **full BC** — the shim's existing `LD B,0` applies.
* `SELDSK` returns a **DPH pointer** — the shim's existing HL=0 inversion applies.
* `SECTRAN` is the identity, so no skew table to worry about.
* **New:** `SETDMA` falls straight through into `SETBNK`, copying the *current*
  bank into the DMA bank. So if the p-System is running in the TPA bank when it
  calls `SETDMA`, the DMA bank is already correct and no extra call is needed.
  That is a pleasant accident rather than something to rely on blindly, but it
  means banking may cost the port nothing at all.

For the handoff, a 2400-block volume (1,228,800 bytes) divides cleanly as
`TRACKS=75, SECTORS=128, BYTES=128` — comfortably inside the 8-bit TRACKS limit
that bit us on MultiComp.

### Console routines, for reference

Not needed — the p-System will drive the Z-19 through ordinary CONOUT — but the
system-bank entry points are `7D3Fh` (input status), `7D54h` (input), `7D82h`
(output), `7D6Fh` (output status), `7E14h` (time), `FE22h`/`FE24h`/`FE26h`/
`FE28h`/`FE2Ah` (console/list/aux device data).

## Remaining unknowns after the disassembly

Much smaller than before:

* Whether the p-System's own use of the stack and page zero conflicts with
  anything CP/M 3 leaves live in common memory. On MultiComp the interpreter
  owns page zero completely; here the BIOS reads nothing from page zero except
  the standard vectors, so this looks safe but is unverified.
* The exact DPB behind the DPH at `FAD0h`, which is built at run time and cannot
  be read from the distribution files. `SHOW.COM` on real hardware will print it.
* Whether the Next's BIOS buffers keyboard input. If it does, the ring buffer
  from SHIM v17 is unnecessary.

## What was genuinely unknown before the disassembly

Three things, in rough order of risk:

1. **Banking during BIOS calls.** `SETBNK` exists and `SETDMA` copies a default
   bank value, so the DMA buffer's bank matters. Whether `SETBNK` must be called
   explicitly before every transfer, and which bank the p-System's buffers would
   need to be in, is the main risk. `biosext.bin` lives outside the 64K space and
   the stub dispatches into it.
2. **Where common memory starts.** CP/M 3 banked keeps the BIOS, resident BDOS
   and system data in a common area at the top of memory. That boundary sets
   TOPRAM, exactly as E600h did on MultiComp. A literal `0FAD0h` appears in
   `SELDSK` as a DPH table base, which *hints* the common area sits high — if it
   begins around F000h the p-System would get roughly 60K, comfortably more than
   the 43K it has on MultiComp. This needs confirming rather than assuming.
3. **Disk parameters for the handoff.** The drives are 16 MB with 512-byte
   physical sectors and 8 KB allocation blocks. CP/M 3's BIOS presents 128-byte
   logical records with its own deblocking underneath, like Grant's, so the
   shim's sector handling should carry over — but TRACKS/SECTORS/BYTES for
   PASBOOT's 13-word handoff must be derived, remembering that **TRACKS must fit
   in 8 bits** (see NOTES.md, workaround 3).

All three are answerable by fully disassembling the 489-byte stub, which is small
enough to read in its entirety without hardware.

## What would carry over unchanged

* The three-stage architecture: `.COM` primary loader, secondary bootstrap,
  SBIOS shim
* The 13-word handoff and the interpreter at 0000h entered at +0200h
* Every disk-convention workaround in NOTES.md (SELDSK return, 8-bit SETTRK/
  SETSEC, 1-based sectors, write type)
* The keyboard ring buffer, if the Next's BIOS turns out to have no input buffer
  of its own — worth checking first, as it may well have one
* The probe methodology in DIAGNOSTICS.md, though far less of it should be needed

## What would not be needed

The entire console translation layer. On MultiComp that is roughly 600 of the
shim's 972 bytes, and it accounted for nearly all the debugging effort.

## Suggested order of work

1. Disassemble `nextbios.prl` completely — 489 bytes, answers questions 1 and 2
2. Confirm the common-memory boundary, which fixes TOPRAM
3. Derive the disk geometry for the handoff
4. Configure `SYSTEM.MISCINFO` for a Z-19 using `SETUP.CODE` — no shim console
5. Port PASBOOT and SECBOOT with the new addresses
6. Write a disk-only shim: `SELDSK` inversion, `LD B,0`, sector base, `SETBNK`

Steps 1 to 3 need no hardware at all.

## Drive layout

Two drives, as on MultiComp, and for the same reason: a p-System volume is not a
CP/M filesystem. It has its own directory at block 2 and its own allocation, so
sharing a drive with CP/M would mean each overwriting the other.

| Drive | Image | Contents |
|-------|-------|----------|
| A | `cpm-a.p3d` | CP/M 3 system, plus `PASBOOT.COM` |
| P | `cpm-p.p3d` *(to create)* | the p-System volume, raw — no CP/M filesystem |

NextZXOS assigns drive letters automatically from the image filenames, so naming
the new image `cpm-p.p3d` makes it **drive P = unit 15** — precisely the unit the
existing shim already forces in `SELDSK`. That constant carries over untouched.

### Getting PASBOOT onto drive A

Much easier than on MultiComp. There, `PASBOOT.COM` had to be written into the
image by hand at offset 32768 with a record count poked into a fabricated
directory entry, because there was no other route. The Next has `IMPORT.COM`:
drop `PASBOOT.COM` on the SD card and import it from the CP/M prompt.

That shortens the iteration loop considerably — assemble, copy one small file,
import, run. Only the p-System volume itself needs writing into a `.p3d` from
the host, and that changes rarely.

## Disk geometry — MEASURED on hardware

`SHOW [DRIVES]` reports, for a 16 MB `.p3d` drive:

```
Records / Track          512
Reserved Tracks            0
Bytes / Physical Record  512
```

Which gives:

| | |
|---|---|
| records per physical sector | 4 |
| bytes per track | 512 x 128 = 65536 (64K) |
| physical sectors per track | 128 |
| tracks on a 16 MB drive | **256** |

Two things follow immediately.

**Reserved tracks is zero**, so a p-System volume placed on its own drive starts
at the very beginning — volume block 0 is physical sector 0, no offset to carry.
(When writing the image from the host, remember the `.p3d` file itself has a
512-byte header in front of the data.)

**256 tracks is one more than the 8-bit TRACKS limit** that bit us on MultiComp
(NOTES.md, workaround 3). The whole 16 MB cannot be described in the handoff. Not
a problem in practice — a p-System volume is far smaller — but it rules out ever
handing the p-System an entire drive.

### Two ways to set the handoff

**Option A — `BYTES=512`, one p-System sector per physical sector**

```
BYTES = 512, SECTORS = 128, TRACKS = 19     (covers 1,245,184 bytes)

BIOS track  = rec >> 7
BIOS sector = rec & 127
```

No deblocking and no read-modify-write. The shim only splits a record number
into track and sector, both by shifting.

**Option B — `BYTES=128`, the geometry we know the interpreter accepts**

```
BYTES = 128, SECTORS = 128, TRACKS = 75     (covers 1,228,800 bytes exactly)

phys    = rec >> 2        quarter = rec & 3
BIOS track = phys >> 7    BIOS sector = phys & 127
```

Reads fetch 512 bytes into a shim buffer and copy `quarter*128` onward to the
DMA address. Writes need **read-modify-write** unless all four quarters happen to
be written in order — which the p-System may well do for whole-block writes, but
that cannot be assumed.

**Try Option A first.** It is a constant rather than code, removes the buffer and
the read-modify-write entirely, and quarters the number of BIOS calls. `BYTES` is
a handoff parameter precisely so it can vary, so there is a good chance the
interpreter simply accepts it. Option B is the proven fallback, and its
deblocking is the same shape as Grant's `rwoper` which is already documented.

Every divisor in both options is a power of two, so the address arithmetic is
shifts and masks throughout — no division routine needed.

## Phase 1 done — PSYSTEM_NEXT.VOL

Built from the working MultiComp volume. 2400 blocks, 25 files, ready to write
into `cpm-p.p3d`.

### MISCINFO was already correct

A pleasant surprise. Our screen codes are **already the Z-19 set**:

```
lead-in ESC   home H   erase-EOS J   erase-EOL K   right C   up A   backspace 08h
```

RomWBW chose those so the `[`-insertion hack would turn them into ANSI, but the
underlying codes are the VT52/Z-19 ones. On the Next they work natively with no
shim. The only change made was **width 79 -> 80**, since the 79 was a MultiComp
workaround for its auto-wrap and the Z-19 is a proper 80-column terminal. If a
full-width line misbehaves, 79 is the fallback — and the Next also has explicit
sequences to enable and disable end-of-line wrapping.

### GOTOXY is the one thing that must change

The volume contains two GOTOXY sources, and the naming is the reverse of what
you would guess:

| File | Emits | Suits |
|------|-------|-------|
| `SAMPLEGOTO.TEXT` | `CHR(27),'Y',CHR(Y+32),CHR(X+32)` | **the Z-19 — this is the one we want** |
| `GOTOXY.TEXT` | `CHR(27),Y+1,';',X+1,'H'` | MultiComp, via the shim's inserted `[` |
| `GOTOXY.CODE` | compiled from `GOTOXY.TEXT` | wrong one for the Next |

`SYSTEM.PASCAL` currently has the ANSI-digit version bound in. On a Z-19 that
emits `ESC 1 ; 1 H`, where `ESC 1` is not a valid Z-19 code — so the terminal
will likely swallow two characters and print `;1H` as stray text. Untidy but
survivable: the outer Command level, the Filer and the Compiler are all mostly
line-oriented and use `ESC H`/`ESC K`, which do work.

**First task after the first successful boot**, therefore:

1. `C(ompile)` `SAMPLEGOTO.TEXT`
2. Run `LIBRARY.CODE` to bind the resulting GOTOXY into `SYSTEM.PASCAL`
3. Reboot

This is the same procedure already carried out once on MultiComp, so it is known
to work. Doing it offline is not practical — binding involves p-code relocation
that would have to be reimplemented, with a high chance of producing a system
that loads and hangs.

### Where the volume goes on the drive

```
file  offset      0 ..     511   P3D header, not part of the disk
disk  offset      0 ..   65535   track 0  = CP/M directory, LEFT INTACT
disk  offset  65536 .. 1294335   track 1+ = the p-System volume
```

So the volume is written at **file offset 66048** (512 header + 65536 for track
0), and the shim adds one track to every address:

```
BIOS track = (rec >> 7) + 1
```

Leaving track 0 alone keeps `cpm-p.p3d` a valid, mountable, apparently-empty
CP/M drive. That matters: an image with no CP/M directory label will not mount
at all — established by trying exactly that, since a drive created here with an
E5-filled directory was rejected while one created on the Next was accepted. The
difference is a single directory label entry (type 20h) in slot 0.

**Rule to observe:** never write a file to P: from the CP/M prompt. CP/M believes
that space is free and will allocate straight over the p-System volume.
