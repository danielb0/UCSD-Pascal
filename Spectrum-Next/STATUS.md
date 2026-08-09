# UCSD p-System IV.0 on the ZX Spectrum Next

UCSD p-System IV.0 runs on a ZX Spectrum Next under CP/M 3: it boots cleanly,
displays correctly on the Next's Z-19 terminal, and takes keyboard input.

## Current versions

| Piece | File | Size | Where it goes |
|---|---|---|---|
| Primary bootstrap | `PASBOOT_NEXT_v9.ASM` | 376 | `PASBOOT.COM` on drive A |
| Secondary bootstrap | `SECBOOT_NEXT_v18.ASM` | 540 (limit 544) | `cpm-p.p3d`, file offset 66048 |
| SBIOS shim | `SHIM_NEXT_v18.ASM` | 453 (limit 480) | `cpm-p.p3d`, offset 66048+544; runs at F000h |

The two reserved blocks hold 1024 bytes and 993 are used. **SECBOOT has only
four bytes spare.** Block 2 is the p-System directory, so a third sector cannot
be taken without moving the whole volume.

The p-System volume occupies `cpm-p.p3d` from block 2 (file offset 67072). Its
SYSTEM.PASCAL and SYSTEM.MISCINFO come from `SYSCPM1_VT52.VOL`; everything else
came from the MultiComp volume.

**Track 0 of `cpm-p.p3d` is the CP/M directory and must stay intact** or the
drive will not mount. Never write a file to P: from the CP/M prompt — CP/M
believes that space is free and will allocate straight over the volume.

## Memory map

```
0000h..35FFh   SYSTEM.INTERP (13824 bytes), and its p-code dispatch table
               occupies 0000h..01FFh
   ...         p-System code, heap and stack
EB80h          TOPRAM
EB80h..ED7Fh   sector buffer (512, MAXBYTES)   ) carved down from
ED80h..EDFFh   sector table  (128, MAXSECTORS) ) NEWTOP = EE00h
EE00h..EF00h   IM 2 vector table, 257 bytes, every one EFh
EFEFh          EI / RETI
F000h..F0C4h   the shim
F2FFh          top of the TPA (CP/M reports 60.5K)
F800h          CP/M 3 BIOS base; (0001h) = F803h
```

## Handoff parameters

```
INTERPBASE 0000h   TRACKS      20     MAXSECTORS -> address ED80h
LOWMEM     0000h   SECTORS    128     MAXBYTES   -> address EB80h
TOPRAM     EB80h   BYTES      512     boot unit    4
SBIOS      F003h   INTERLEAVE   1     FIRSTTRACK   1, SKEW 0
```

`BYTES=512` works. One p-System sector is one physical sector, so no deblocking
is needed anywhere.

## What had to be discovered

**The BIOS disk entries need the system bank paged in.** READ and WRITE
dispatch to 7C98h/7CC8h, which only exist in the system bank, and nothing on
that path pages it in — their normal caller is the banked BDOS. Route them
through the BIOS's own wrapper at `base+00FFh`, which saves SP, switches to a
stack in common memory, pages the bank in, `JP (HL)`, and restores. SELDSK,
SETTRK, SETSEC and SETDMA are plain stores and need no wrapper. SETDMA also
sets the DMA bank from the current configuration, so no SETBNK call is needed.

**CP/M 3 on the Next runs in IM 2** with I = 09h, its vector table at
0900h..09FFh — inside the TPA — and its handler at FE0Ah. The interpreter loads
over 0000h..35FFh and destroys that table every boot. This was the single
biggest cause of trouble: with interrupts enabled the CPU fetched a vector out
of p-code, and with them disabled anything inside the BIOS that re-enabled them
did the same. The fix is our own uniform 257-byte table above TOPRAM pointing
at an EI/RETI stub, so an interrupt is harmless wherever it is enabled.

**The p-System's SBIOS offsets are CP/M's shifted by three**: `SBIOS+24` is
SELDSK, `+27` SETTRK, `+30` SETSEC, `+33` SETDMA, `+36` READ, `+39` WRITE. That
is correct for `SBIOS = base+3`, which is what SECBOOT passes.

**The interpreter only permits READ, WRITE and HOME on drive 0** — it checks
the drive saved by the last SELDSK against 1 at 23C5h. The shim forcing C=15 is
safe because 2399h saves the interpreter's own C before jumping.

**TRACKS is checked after FIRSTTRACK is added** (20EDh), so it must cover the
volume plus the offset. 19 was one short; 20 is correct.

## Bugs found and fixed, in order

1. **The handoff stack was inside the BIOS.** MultiComp's `SP = (BOOT+1)-17` is
   a safe gap under CP/M 2.2; under CP/M 3 it is `base+00F2h`, on top of CONST
   and CONIN.
2. **SECBOOT never set SP after the carve.** MultiComp does `LD SP,HL`; the port
   had dropped it, so the interpreter ran on a stack inside its own sector
   buffers. Symptom: purple border.
3. **READ and BIOSJMP fetched the BIOS address from `(BOOT+1)`** — page zero,
   which the interpreter load overwrites partway through.
4. **TRACKS off by one** (see above).
5. **TOPRAM set to C000h**, on the mistaken assumption that the common bank was
   off limits. C000h..F1FFh is ordinary TPA RAM; that cost the p-System 12.5K.
6. **Interrupts** (see above) — by far the most expensive to find.
7. **The display used an ANSI GOTOXY.** Fixed by taking SYSTEM.PASCAL and
   SYSTEM.MISCINFO from `SYSCPM1_VT52.VOL`. Those two files differ from
   `SYSCPM1.VOL` only in MISCINFO, which proves cursor addressing on this
   system is driven from MISCINFO rather than a compiled-in GOTOXY.

## The keyboard — solved by bypassing the BIOS

The BIOS console cannot supply input here. It fills its buffer from the
NextZXOS interrupt chain, and that chain cannot run once the interpreter owns
low memory. `SECBOOT_NEXT_v14DIAG.ASM` proves it: load the interpreter
normally, chain the IM 2 vector to FE0Ah, enable interrupts, then print a star
twice a second in a loop. Exactly one star appears — the handler is entered on
the first tick and never returns. Restoring CP/M's `JP` at 0038h (the IM 1
route) fails identically, and USERF function 4 with A=0 makes no difference.

The decisive clue was that **a PS/2 keyboard failed in exactly the same way**.
On the Next the FPGA merges PS/2 into the ordinary Spectrum key matrix, so both
keyboards arrive by the same route — meaning the fault was never in either
keyboard's hardware path, and the matrix itself must still be readable.

So the shim reads it directly. `IN A,(0FEh)` with the row select in B returns
key states straight from the ULA, and AllRam mode remaps memory, not I/O, so it
works normally under CP/M. CONST and CONIN are implemented in hardware terms and
the BIOS console is bypassed for input entirely; output still goes through
CONOUT, which always worked. This is the same approach the MultiComp shim takes
with that machine's ACIA: drive the hardware, do not rely on the OS.

It is fast and responsive in use.

### Key map

Letters produce UPPER CASE — UCSD's command line and its Pascal are
conventionally upper case, and lower case is not reachable in this version. If
that turns out to matter, the plain and CAPS letter cases simply swap over.

```
CAPS SHIFT + letter    control code (CTRL-A = 01 ... CTRL-Z = 1A)
CAPS SHIFT + SPACE     ESC (1Bh)
CAPS SHIFT + 0         backspace (08h)
SYMBOL SHIFT + key     punctuation (table at the end of SHIM_NEXT_v18.ASM)
```

Punctuation follows the Spectrum's printed legends where they exist — SS+Z is
`:`, SS+M is `.`, SS+N is `,`, SS+J is `-` — and fills the gaps with what Pascal
needs: brackets on SS+Q and SS+W, braces on SS+D and SS+F.

### Behaviour to verify against other implementations

Two things are described here as they are, rather than as shortcomings, because
it is not yet established that they differ from UCSD p-System elsewhere. Worth
checking against the MultiComp, TI-99/4A, BBC Micro and Apple II systems before
treating either as a defect.

- **No auto-repeat.** A key must be released before it registers again. Our
  reason is that without an interrupt there is no timebase to measure a repeat
  delay against, and a bare "still pressed" test would flood the p-System. But
  several UCSD implementations may not repeat either.
- **Upper case only.** Chosen because UCSD's command line and its Pascal are
  conventionally upper case. Some p-System versions are upper-case-only
  regardless, in which case this is not a restriction at all. If lower case is
  wanted, the plain and CAPS letter cases simply swap over in the table.

One genuine difference: the BIOS's own key mappings (BREAK as ESC, EXTEND as
CTRL, the cursor keys) do **not** apply, because the BIOS is no longer involved
in input. The map above is the whole story.

## Diagnostic lesson worth keeping

Three shim builds differing only in console instrumentation produced three
different failures — err 6, err 13, and a hang — each repeatable on its own.
That pattern was the real evidence, and it pointed at a race rather than at any
parameter. Adding instrumentation was itself perturbing the system, so the
measurements became less trustworthy the more of them there were. The way out
was to make the machine deterministic first and only then debug it.

`BYTES=512` was wrongly blamed twice along the way: cleared once on the strength
of the interpreter's divide routine alone, then reinstated when the software
turned out byte-identical to MultiComp's. It was innocent throughout.

## Tools

`z80dis.py` (in the outputs folder) is a small Z80 disassembler written for this
work. Disassembling SYSTEM.INTERP is what settled most of the questions above:
the twelve handoff parameters land at 1E89h, and searching for instructions that
read that table leads straight to the code that validates them.
